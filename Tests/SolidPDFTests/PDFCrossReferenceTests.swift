import Foundation
@testable import SolidPDF
import SolidIO
import Testing

@Suite
struct PDFCrossReferenceTests {
  @Test(arguments: PDFVersion.allCases)
  func parsesWriterCrossReferenceFormats(_ version: PDFVersion) async throws {
    let encoded = try makeWriterDocument(version: version)
    let index = try await parse(encoded.data)
    #expect(index.version.rawValue == version.rawValue)
    #expect(index.root.objectNumber == 1)
    #expect(index.entries[1] == .uncompressed(offset: 15, generationNumber: 0))
    #expect(index.identifier?.count == 2)
    #expect(index.entries.count == (version == .v2_0 ? 4 : 3))
  }

  @Test
  func parsesFlateCrossReferenceStreamWithExplicitWidths() async throws {
    let fixture = try makeFlateCrossReferenceStream()
    let index = try await parse(fixture)
    #expect(index.version == .v1_7)
    #expect(index.root.objectNumber == 1)
    guard case .uncompressed(let offset, 0) = index.entries[1] else {
      Issue.record("Expected object 1 to be uncompressed")
      return
    }
    #expect(offset == 9)
    guard case .uncompressed(_, 0) = index.entries[2] else {
      Issue.record("Expected the xref stream object to index itself")
      return
    }
  }

  @Test
  func rejectsIncrementalEncryptedAndOverlappingTables() async throws {
    let incremental = classicFixture(extraTrailer: "/Prev 1")
    await #expect(throws: PDFParsingError.self) { _ = try await parse(incremental) }

    let encrypted = classicFixture(extraTrailer: "/Encrypt 2 0 R")
    await #expect(throws: PDFParsingError.self) { _ = try await parse(encrypted) }

    let overlap = Data(
      ("%PDF-1.7\n"
        + "1 0 obj\n<< /Type /Catalog >>\nendobj\n"
        + "xref\n0 2\n0000000000 65535 f \n0000000009 00000 n \n"
        + "1 1\n0000000009 00000 n \n"
        + "trailer\n<< /Size 2 /Root 1 0 R >>\n"
        + "startxref\n45\n%%EOF\n").utf8
    )
    await #expect(throws: PDFParsingError.self) { _ = try await parse(overlap) }
  }

  @Test
  func rejectsUnsupportedStructuralFilterAndTrailingGarbage() async throws {
    var unsupported = try makeFlateCrossReferenceStream(filterName: "LZWDecode")
    await #expect(throws: PDFParsingError.self) { _ = try await parse(unsupported) }

    unsupported = classicFixture()
    unsupported.append(Data("garbage".utf8))
    await #expect(throws: PDFParsingError.self) { _ = try await parse(unsupported) }
  }

  private func parse(_ data: Data) async throws -> PDFCrossReferenceIndex {
    let session = try await PDFDataInputSource(data).makeSession()
    let options = PDFParsingOptions(sourceWindowByteCount: 11)
    let reader = try await PDFSourceReader(session: session, options: options)
    do {
      let index = try await PDFCrossReferenceParser(reader: reader, options: options).parse()
      await reader.close()
      return index
    } catch {
      await reader.close()
      throw error
    }
  }

  private func makeWriterDocument(version: PDFVersion) throws -> PDFEncodedDocument {
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(version: version, compressionLevel: 0)
    )
    let root = try writer.reserveObject()
    let pages = try writer.reserveObject()
    try writer.write(.dictionary(["Type": .name("Catalog"), "Pages": .reference(pages)]), to: root)
    try writer.write(
      .dictionary(["Type": .name("Pages"), "Count": .integer(0), "Kids": .array([])]),
      to: pages
    )
    return try writer.finish(root: root, pageCount: 0)
  }

  private func classicFixture(extraTrailer: String = "") -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    let objectOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog >>\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n0 2\n".utf8))
    data.append(Data("0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", objectOffset).utf8))
    data.append(Data("trailer\n<< /Size 2 /Root 1 0 R \(extraTrailer) >>\n".utf8))
    data.append(Data("startxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }

  private func makeFlateCrossReferenceStream(
    filterName: String = "FlateDecode"
  ) throws -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    let rootOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog >>\nendobj\n".utf8))
    let xrefOffset = data.count
    var entries = Data()
    appendEntry(type: 0, field2: 0, field3: 65_535, to: &entries)
    appendEntry(type: 1, field2: rootOffset, field3: 0, to: &entries)
    appendEntry(type: 1, field2: xrefOffset, field3: 0, to: &entries)
    let encoder = try ZlibStreamEncoder(compressionLevel: 0)
    var compressed = try encoder.process(entries)
    compressed.append(try encoder.finish() ?? Data())
    data.append(
      Data(
        ("2 0 obj\n"
          + "<< /Type /XRef /Size 3 /Root 1 0 R /W [1 4 2] "
          + "/Filter /\(filterName) /Length \(compressed.count) >>\nstream\n").utf8
      )
    )
    data.append(compressed)
    data.append(Data("\nendstream\nendobj\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }

  private func appendEntry(type: UInt8, field2: Int, field3: Int, to data: inout Data) {
    data.append(type)
    data.append(UInt8((field2 >> 24) & 0xFF))
    data.append(UInt8((field2 >> 16) & 0xFF))
    data.append(UInt8((field2 >> 8) & 0xFF))
    data.append(UInt8(field2 & 0xFF))
    data.append(UInt8((field3 >> 8) & 0xFF))
    data.append(UInt8(field3 & 0xFF))
  }
}
