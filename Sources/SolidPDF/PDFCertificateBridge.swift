import Crypto
import Foundation
import SwiftASN1
import X509

enum PDFCertificateBridge {
  static func parse(_ value: PDFCertificate) throws -> Certificate {
    try Certificate(derEncoded: [UInt8](value.derRepresentation))
  }

  static func portable(_ certificate: Certificate) throws -> PDFCertificate {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    let bytes = Data(serializer.serializedBytes)
    return PDFCertificate(
      derRepresentation: bytes,
      serialNumber: Data(certificate.serialNumber.bytes),
      subject: certificate.subject.description,
      issuer: certificate.issuer.description,
      notValidBefore: certificate.notValidBefore,
      notValidAfter: certificate.notValidAfter,
      sha256Fingerprint: Data(SHA256.hash(data: bytes))
    )
  }

  static func issuerDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.issuer.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
  }
}
