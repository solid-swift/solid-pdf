import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFEmbeddedAssetTests {
  @Test
  func enumeratesEmbeddedFilesAssociationsAndCollectionsWithoutOpeningContents() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let sequence = try await document.embeddedFiles()
    let file = try #require(try await sequence.next())
    #expect(file.nameTreeKey?.bytes == Data("asset.txt".utf8))
    #expect(file.fileSpecification.unicodeFilename == "asset.txt")
    #expect(file.subtype == "text/plain")
    #expect(file.declaredSize == 10)
    #expect(file.checksum?.hex == "44290cefe42924d04a92d99428a95f27")
    #expect(try await sequence.next() == nil)

    let associations = try await document.associatedFiles()
    #expect(associations.count == 2)
    #expect(associations.allSatisfy { $0.relationship == .data })
    #expect(Set(associations.map(\.fileSpecification.identifier)).count == 1)
    #expect(associations.contains { if case .catalog = $0.owner { true } else { false } })
    #expect(associations.contains { if case .annotation = $0.owner { true } else { false } })

    let collection = try #require(try await document.collection())
    #expect(collection.view == .details)
    #expect(collection.initialDocument?.bytes == Data("asset.txt".utf8))
    #expect(collection.schema["Name"]?.displayName == "Name")
    #expect(collection.items.count == 1)
    #expect(collection.sort == .init(fields: ["Name"], ascending: [true]))

    #expect(try await document.decodedBytes(of: file) == Data("attachment".utf8))
    await document.close()
  }

  @Test
  func validatesSizeAndChecksumOnlyAfterCompleteConsumption() async throws {
    let badSize = try await PDFDocument(source: PDFDataInputSource(fixture(size: 11)))
    let sizeSequence = try await badSize.embeddedFiles()
    let sizeFile = try #require(try await sizeSequence.next())
    await #expect(throws: PDFParsingError.self) {
      _ = try await badSize.decodedBytes(of: sizeFile)
    }
    await badSize.close()

    let badChecksum = try await PDFDocument(
      source: PDFDataInputSource(fixture(checksum: "00000000000000000000000000000000"))
    )
    let checksumSequence = try await badChecksum.embeddedFiles()
    let checksumFile = try #require(try await checksumSequence.next())
    let stream = try await badChecksum.decodedStream(of: checksumFile)
    _ = try await stream.next()
    await stream.close()
    await badChecksum.close()
  }

  private func fixture(
    size: Int = 10,
    checksum: String = "44290cefe42924d04a92d99428a95f27"
  ) -> Data {
    let payload = Data("attachment".utf8)
    var embedded = Data(
      "<< /Type /EmbeddedFile /Subtype /text#2Fplain /Params << /Size \(size) /CheckSum <\(checksum)> /CreationDate (D:20240822153045Z) >> /Length \(payload.count) >>\nstream\n".utf8
    )
    embedded.append(payload)
    embedded.append(Data("\nendstream".utf8))
    return makePDF(objects: [
      Data("<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles 5 0 R >> /AF [6 0 R] /Collection 9 0 R >>".utf8),
      Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
      Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources <<>> /Annots [8 0 R] >>".utf8),
      embedded,
      Data("<< /Names [(asset.txt) 6 0 R] >>".utf8),
      Data("<< /Type /Filespec /F (asset.txt) /UF (asset.txt) /EF << /F 4 0 R >> /AFRelationship /Data /CI << /Name (Asset) >> >>".utf8),
      Data("null".utf8),
      Data("<< /Type /Annot /Subtype /FileAttachment /Rect [0 0 10 10] /FS 6 0 R >>".utf8),
      Data("<< /View /D /D (asset.txt) /Schema << /Name << /Subtype /S /N (Name) /O 1 >> >> /Sort << /S /Name /A true >> >>".utf8),
    ])
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

private extension Data {
  var hex: String { map { String(format: "%02x", $0) }.joined() }
}
