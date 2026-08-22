import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFSignatureContainerTests {
  @Test
  func parsesBoundedCMSSignerMetadataAndZeroPadding() throws {
    let cms = cmsFixture()
    var padded = cms
    padded.append(contentsOf: [0, 0, 0])
    let container = try PDFCMSParser(limits: .init()).parse(padded, format: .pkcs7Detached)
    #expect(container.derRepresentation == cms)
    #expect(container.contentTypeIdentifier == "1.2.840.113549.1.7.1")
    #expect(container.signers.count == 1)
    #expect(container.signers[0].digestAlgorithm == .sha256)
    #expect(container.signers[0].signatureAlgorithm == .rsaPKCS1v15)
    #expect(container.signers[0].messageDigest == Data(repeating: 0xA5, count: 32))

    var invalid = cms
    invalid.append(1)
    #expect(throws: (any Error).self) {
      _ = try PDFCMSParser(limits: .init()).parse(invalid, format: .pkcs7Detached)
    }
  }

  @Test
  func findsExactHexadecimalContentsToken() throws {
    let source = Data("3 0 obj\n<< /Reason (not /Contents <00>) /Contents <30 03 01> >>\nendobj".utf8)
    let token = try PDFSignatureSourceScanner.contentsToken(in: source, absoluteOffset: 100)
    #expect(token.bytes == Data([0x30, 0x03, 0x01]))
    #expect(token.range.offset == 150)
    #expect(source.subdata(in: Int(token.range.offset - 100)..<Int(token.range.endOffset - 100)) == Data("<30 03 01>".utf8))
  }

  @Test
  func discoversCatalogCertificationSignatureWithSourceProvenance() async throws {
    let cms = cmsFixture()
    let signature = Data(
      "<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /ByteRange [0 1] /Contents <\(cms.map { String(format: "%02X", $0) }.joined())> /Reference [<< /TransformMethod /DocMDP /TransformParams << /P 1 >> >>] >>".utf8
    )
    let bytes = makePDF(objects: [
      Data("<< /Type /Catalog /Pages 2 0 R /Perms << /DocMDP 3 0 R >> >>".utf8),
      Data("<< /Type /Pages /Kids [] /Count 0 >>".utf8),
      signature,
    ])
    let document = try await PDFDocument(source: PDFDataInputSource(bytes))
    let resolved = try await document.resolve(try .init(objectNumber: 3, generationNumber: 0))
    if let range = resolved.sourceRange {
      let raw = bytes.subdata(in: Int(range.offset)..<Int(range.endOffset))
      _ = try PDFSignatureSourceScanner.contentsToken(in: raw, absoluteOffset: range.offset)
    }
    let signatures = try await document.signatures()
    #expect(signatures.count == 1)
    #expect(signatures[0].kind == .certification)
    #expect(signatures[0].dictionaryReference?.objectNumber == 3)
    #expect(signatures[0].contentsSourceRange != nil)
    #expect(signatures[0].container?.signers.count == 1)
    #expect(signatures[0].signedRevision == document.latestRevision.identifier)
    #expect(signatures[0].transforms == [.docMDP(.init(permissionLevel: 1, rawParameters: ["P": .integer(1)]))])
    await document.close()
  }

  private func cmsFixture() -> Data {
    let sha256 = algorithm("2.16.840.1.101.3.4.2.1")
    let messageDigest = sequence([
      oid("1.2.840.113549.1.9.4"),
      set([octet(Data(repeating: 0xA5, count: 32))]),
    ])
    let signer = sequence([
      integer(1),
      sequence([sequence([]), integer(1)]),
      sha256,
      tagged(0, [messageDigest]),
      algorithm("1.2.840.113549.1.1.1"),
      octet(Data([1, 2, 3])),
    ])
    let signedData = sequence([
      integer(1),
      set([sha256]),
      sequence([oid("1.2.840.113549.1.7.1")]),
      set([signer]),
    ])
    return sequence([oid("1.2.840.113549.1.7.2"), tagged(0, [signedData])])
  }

  private func algorithm(_ identifier: String) -> Data {
    sequence([oid(identifier), tlv(0x05, Data())])
  }

  private func sequence(_ values: [Data]) -> Data { tlv(0x30, values.reduce(into: Data()) { $0.append($1) }) }
  private func set(_ values: [Data]) -> Data { tlv(0x31, values.reduce(into: Data()) { $0.append($1) }) }
  private func tagged(_ number: UInt8, _ values: [Data]) -> Data {
    tlv(0xA0 | number, values.reduce(into: Data()) { $0.append($1) })
  }
  private func integer(_ value: UInt8) -> Data { tlv(0x02, Data([value])) }
  private func octet(_ value: Data) -> Data { tlv(0x04, value) }

  private func oid(_ text: String) -> Data {
    let components = text.split(separator: ".").compactMap { Int($0) }
    var bytes = [UInt8(components[0] * 40 + components[1])]
    for component in components.dropFirst(2) {
      var encoded = [UInt8(component & 0x7F)]
      var remaining = component >> 7
      while remaining > 0 {
        encoded.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
        remaining >>= 7
      }
      bytes.append(contentsOf: encoded)
    }
    return tlv(0x06, Data(bytes))
  }

  private func tlv(_ tag: UInt8, _ content: Data) -> Data {
    var result = Data([tag])
    if content.count < 128 {
      result.append(UInt8(content.count))
    } else if content.count < 256 {
      result.append(0x81)
      result.append(UInt8(content.count))
    } else {
      let length = UInt16(content.count).bigEndian
      withUnsafeBytes(of: length) { bytes in
        result.append(0x82)
        result.append(contentsOf: bytes)
      }
    }
    result.append(content)
    return result
  }

  private func makePDF(objects: [Data]) -> Data {
    var data = Data("%PDF-2.0\n".utf8)
    var offsets = [Int]()
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n".utf8))
      data.append(object)
      data.append(Data("\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}
