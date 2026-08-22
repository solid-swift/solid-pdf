import Crypto
import Foundation
import SwiftASN1
import X509

struct PDFCMSParser {
  private struct ParsedCertificate {
    let value: PDFCertificate
    let issuerDER: Data
  }

  private let limits: PDFParsingLimits

  init(limits: PDFParsingLimits) {
    self.limits = limits
  }

  func parse(_ paddedData: Data, format: PDFSignatureContainerFormat) throws -> PDFSignatureContainer {
    guard paddedData.count <= limits.maximumAuthenticityScratchBytes else { throw PDFDERError.limitExceeded }
    var prefixParser = PDFDERParser(
      data: paddedData,
      maximumDepth: limits.maximumASN1Nesting,
      maximumNodes: limits.maximumAuthenticityScratchBytes
    )
    let root = try prefixParser.parsePrefix()
    let der = paddedData.subdata(in: root.fullRange)
    guard paddedData[root.fullRange.upperBound...].allSatisfy({ $0 == 0 }) else {
      throw PDFDERError.trailingData(root.fullRange.upperBound)
    }
    _ = try DER.parse([UInt8](der))
    if case .x509RSASHA1 = format {
      return PDFSignatureContainer(format: format, derRepresentation: der)
    }
    try root.requireUniversal(16)
    guard root.children.count == 2 else { throw PDFDERError.malformed(root.fullRange.lowerBound) }
    let outerType = try root.children[0].objectIdentifier(in: der)
    guard outerType == "1.2.840.113549.1.7.2" else { throw PDFDERError.malformed(root.fullRange.lowerBound) }
    let wrapper = root.children[1]
    guard wrapper.tagClass == .contextSpecific, wrapper.tagNumber == 0, wrapper.children.count == 1 else {
      throw PDFDERError.malformed(wrapper.fullRange.lowerBound)
    }
    return try parseSignedData(wrapper.children[0], data: der, format: format)
  }

  private func parseSignedData(
    _ node: PDFDERNode,
    data: Data,
    format: PDFSignatureContainerFormat
  ) throws -> PDFSignatureContainer {
    try node.requireUniversal(16)
    guard node.children.count >= 4 else { throw PDFDERError.malformed(node.fullRange.lowerBound) }
    let contentInfo = node.children[2]
    try contentInfo.requireUniversal(16)
    guard let contentTypeNode = contentInfo.children.first else {
      throw PDFDERError.malformed(contentInfo.fullRange.lowerBound)
    }
    let contentType = try contentTypeNode.objectIdentifier(in: data)
    let encapsulatedContent = try contentInfo.children.dropFirst().first.map { wrapper -> Data in
      guard wrapper.tagClass == .contextSpecific, wrapper.tagNumber == 0, wrapper.children.count == 1 else {
        throw PDFDERError.malformed(wrapper.fullRange.lowerBound)
      }
      let octets = wrapper.children[0]
      try octets.requireUniversal(4)
      return octets.content(in: data)
    }
    var certificates = [ParsedCertificate]()
    var signerSet: PDFDERNode?
    for child in node.children.dropFirst(3) {
      if child.tagClass == .contextSpecific, child.tagNumber == 0 {
        certificates = try parseCertificates(child, data: data)
      } else if child.tagClass == .universal, child.tagNumber == 17 {
        signerSet = child
      }
    }
    guard let signerSet else { throw PDFDERError.malformed(node.fullRange.lowerBound) }
    guard signerSet.children.count <= limits.maximumCMSSigners else { throw PDFDERError.limitExceeded }
    let signers = try signerSet.children.map { try parseSigner($0, data: data, certificates: certificates) }
    return PDFSignatureContainer(
      format: format,
      derRepresentation: data,
      contentTypeIdentifier: contentType,
      encapsulatedContent: encapsulatedContent,
      signers: signers,
      certificates: certificates.map(\.value),
      timestampTokens: []
    )
  }

  private func parseCertificates(_ wrapper: PDFDERNode, data: Data) throws -> [ParsedCertificate] {
    guard wrapper.children.count <= limits.maximumCertificates else { throw PDFDERError.limitExceeded }
    return try wrapper.children.compactMap { node in
      guard node.tagClass == .universal, node.tagNumber == 16 else { return nil }
      let bytes = node.bytes(in: data)
      let certificate = try Certificate(derEncoded: [UInt8](bytes))
      var serializer = DER.Serializer()
      try certificate.issuer.serialize(into: &serializer)
      return ParsedCertificate(
        value: PDFCertificate(
          derRepresentation: bytes,
          serialNumber: Data(certificate.serialNumber.bytes),
          subject: certificate.subject.description,
          issuer: certificate.issuer.description,
          notValidBefore: certificate.notValidBefore,
          notValidAfter: certificate.notValidAfter,
          sha256Fingerprint: Data(SHA256.hash(data: bytes))
        ),
        issuerDER: Data(serializer.serializedBytes)
      )
    }
  }

  private func parseSigner(
    _ node: PDFDERNode,
    data: Data,
    certificates: [ParsedCertificate]
  ) throws -> PDFSignatureSigner {
    try node.requireUniversal(16)
    guard node.children.count >= 5 else { throw PDFDERError.malformed(node.fullRange.lowerBound) }
    var index = 1
    let identifierNode = node.children[index]
    index += 1
    let issuerAndSerial: PDFSignatureIssuerAndSerialNumber?
    let subjectKeyIdentifier: Data?
    if identifierNode.tagClass == .universal, identifierNode.tagNumber == 16,
      identifierNode.children.count == 2
    {
      issuerAndSerial = try PDFSignatureIssuerAndSerialNumber(
        issuerDER: identifierNode.children[0].bytes(in: data),
        serialNumber: identifierNode.children[1].unsignedInteger(in: data)
      )
      subjectKeyIdentifier = nil
    } else if identifierNode.tagClass == .contextSpecific, identifierNode.tagNumber == 0 {
      issuerAndSerial = nil
      subjectKeyIdentifier = identifierNode.content(in: data)
    } else {
      throw PDFDERError.malformed(identifierNode.fullRange.lowerBound)
    }
    let digestAlgorithm = try algorithmIdentifier(node.children[index], data: data).digest
    index += 1
    var signedAttributes: [PDFDERNode] = []
    if index < node.children.count,
      node.children[index].tagClass == .contextSpecific,
      node.children[index].tagNumber == 0
    {
      signedAttributes = node.children[index].children
      index += 1
    }
    guard index + 1 < node.children.count else { throw PDFDERError.malformed(node.fullRange.lowerBound) }
    let signatureAlgorithm = try algorithmIdentifier(node.children[index], data: data).signature
    index += 1
    let signatureNode = node.children[index]
    try signatureNode.requireUniversal(4)
    index += 1
    let unsignedAttributes = index < node.children.count ? node.children[index].children : []
    let signed = try attributes(signedAttributes, data: data)
    let unsigned = try attributes(unsignedAttributes, data: data)
    let matchedCertificate = certificates.first { candidate in
      if let issuerAndSerial {
        return candidate.issuerDER == issuerAndSerial.issuerDER
          && candidate.value.serialNumber == issuerAndSerial.serialNumber
      }
      return false
    }?.value
    return PDFSignatureSigner(
      issuerAndSerialNumber: issuerAndSerial,
      subjectKeyIdentifier: subjectKeyIdentifier,
      digestAlgorithm: digestAlgorithm,
      signatureAlgorithm: signatureAlgorithm,
      signature: signatureNode.content(in: data),
      messageDigest: signed.messageDigest,
      signingTime: signed.signingTime,
      certificate: matchedCertificate,
      unknownSignedAttributeIdentifiers: signed.unknown,
      unknownUnsignedAttributeIdentifiers: unsigned.unknown
    )
  }

  private func algorithmIdentifier(
    _ node: PDFDERNode,
    data: Data
  ) throws -> (digest: PDFDigestAlgorithm, signature: PDFSignatureAlgorithm) {
    try node.requireUniversal(16)
    guard let oidNode = node.children.first else { throw PDFDERError.malformed(node.fullRange.lowerBound) }
    let oid = try oidNode.objectIdentifier(in: data)
    return (digestAlgorithm(oid), signatureAlgorithm(oid))
  }

  private func attributes(
    _ nodes: [PDFDERNode],
    data: Data
  ) throws -> (messageDigest: Data?, signingTime: Date?, unknown: [String]) {
    var messageDigest: Data?
    var signingTime: Date?
    var unknown = [String]()
    for node in nodes {
      try node.requireUniversal(16)
      guard node.children.count == 2 else { throw PDFDERError.malformed(node.fullRange.lowerBound) }
      let oid = try node.children[0].objectIdentifier(in: data)
      let values = node.children[1]
      try values.requireUniversal(17)
      switch oid {
      case "1.2.840.113549.1.9.3": break
      case "1.2.840.113549.1.9.4":
        guard values.children.count == 1 else { throw PDFDERError.malformed(values.fullRange.lowerBound) }
        try values.children[0].requireUniversal(4)
        messageDigest = values.children[0].content(in: data)
      case "1.2.840.113549.1.9.5":
        guard values.children.count == 1 else { throw PDFDERError.malformed(values.fullRange.lowerBound) }
        signingTime = try parseTime(values.children[0], data: data)
      default: unknown.append(oid)
      }
    }
    return (messageDigest, signingTime, unknown)
  }

  private func parseTime(_ node: PDFDERNode, data: Data) throws -> Date {
    guard node.tagClass == .universal, node.tagNumber == 23 || node.tagNumber == 24,
      let text = String(data: node.content(in: data), encoding: .ascii)
    else { throw PDFDERError.malformed(node.fullRange.lowerBound) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    let formats = node.tagNumber == 23 ? ["yyMMddHHmmss'Z'", "yyMMddHHmm'Z'"] : ["yyyyMMddHHmmss'Z'"]
    for format in formats {
      formatter.dateFormat = format
      if let date = formatter.date(from: text) { return date }
    }
    throw PDFDERError.malformed(node.fullRange.lowerBound)
  }

  private func digestAlgorithm(_ oid: String) -> PDFDigestAlgorithm {
    switch oid {
    case "1.3.14.3.2.26", "1.2.840.113549.1.1.5": .sha1
    case "2.16.840.1.101.3.4.2.4": .sha224
    case "2.16.840.1.101.3.4.2.1", "1.2.840.113549.1.1.11": .sha256
    case "2.16.840.1.101.3.4.2.2", "1.2.840.113549.1.1.12": .sha384
    case "2.16.840.1.101.3.4.2.3", "1.2.840.113549.1.1.13": .sha512
    default: .unsupported(oid)
    }
  }

  private func signatureAlgorithm(_ oid: String) -> PDFSignatureAlgorithm {
    switch oid {
    case "1.2.840.113549.1.1.1", "1.2.840.113549.1.1.5", "1.2.840.113549.1.1.11",
      "1.2.840.113549.1.1.12", "1.2.840.113549.1.1.13": .rsaPKCS1v15
    case "1.2.840.113549.1.1.10": .rsaPSS
    case "1.2.840.10045.4.1", "1.2.840.10045.4.3.1", "1.2.840.10045.4.3.2",
      "1.2.840.10045.4.3.3", "1.2.840.10045.4.3.4": .ecdsa
    case "1.3.101.112": .ed25519
    default: .unsupported(oid)
    }
  }
}
