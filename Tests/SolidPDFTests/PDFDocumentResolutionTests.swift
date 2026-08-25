import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFDocumentResolutionTests {
  @Test(arguments: PDFVersion.allCases)
  func lazilyResolvesWriterObjectsAndIndirectStreamLengths(_ version: PDFVersion) async throws {
    let encoded = try makeWriterDocument(version: version)
    let document = try await PDFDocument(source: PDFDataInputSource(encoded.data))
    #expect(document.version.rawValue == version.rawValue)
    let catalog = try await document.resolve(document.root)
    guard case .value(.dictionary(let catalogDictionary)) = catalog.value,
      let pagesReference = catalogDictionary.pdfReference(named: "Pages")
    else {
      Issue.record("Expected a catalog dictionary")
      return
    }
    let pages = try await document.resolve(pagesReference)
    guard case .value(.dictionary(let pagesDictionary)) = pages.value,
      let kids = pagesDictionary.pdfArray(named: "Kids"),
      case .reference(let pageReference) = kids.first
    else {
      Issue.record("Expected a pages dictionary")
      return
    }
    let page = try await document.resolve(pageReference)
    guard case .value(.dictionary(let pageDictionary)) = page.value,
      let contentsReference = pageDictionary.pdfReference(named: "Contents")
    else {
      Issue.record("Expected a page dictionary")
      return
    }
    let contents = try await document.resolve(contentsReference)
    guard case .stream(let stream) = contents.value else {
      Issue.record("Expected a stream")
      return
    }
    #expect(try await document.encodedBytes(of: stream) == Data("0 0 m 1 1 l S\n".utf8))
    #expect(contents.provenance == .file)
    #expect(contents.sourceRange != nil)
    await document.close()
    await #expect(throws: PDFParsingError.documentClosed) {
      _ = try await document.resolve(document.root)
    }
  }

  @Test
  func resolvesObjectStreamMembersWithExactProvenance() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(objectStreamFixture()))
    let reference = try PDFObjectReference(objectNumber: 3, generationNumber: 0)
    let object = try await document.resolve(reference)
    #expect(object.sourceRange == nil)
    #expect(
      object.provenance
        == .objectStream(
          container: try PDFObjectReference(objectNumber: 2, generationNumber: 0),
          index: 0
        )
    )
    #expect(object.value == .value(.dictionary(["Value": .integer(42)])))
    await document.close()
  }

  @Test
  func acceptsAStreamWithoutTheRecommendedLineEndingBeforeEndstream() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(streamWithoutTrailingLineEndingFixture())
    )
    let streamReference = try PDFObjectReference(objectNumber: 1, generationNumber: 0)
    guard case .stream(let stream) = try await document.resolve(streamReference).value else {
      Issue.record("Expected the root object to be a stream")
      return
    }
    #expect(try await document.encodedBytes(of: stream) == Data([0x00, 0xFF, 0x0D]))
    await document.close()
  }

  @Test
  func detectsIndirectLengthCyclesAndGenerationMismatches() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(cyclicLengthFixture()))
    let first = try PDFObjectReference(objectNumber: 1, generationNumber: 0)
    await #expect(throws: PDFParsingError.self) { _ = try await document.resolve(first) }
    let wrongGeneration = try PDFObjectReference(objectNumber: 3, generationNumber: 1)
    await #expect(throws: PDFParsingError.unresolvedReference(wrongGeneration)) {
      _ = try await document.resolve(wrongGeneration)
    }
    await document.close()
  }

  @Test
  func coalescesConcurrentResolutionAndSupportsFileSources() async throws {
    let encoded = try makeWriterDocument(version: .v1_7)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("input.pdf")
    try encoded.data.write(to: url)
    let document = try await PDFDocument(source: PDFFileInputSource(url: url))
    let root = document.root
    let values = try await withThrowingTaskGroup(of: PDFIndirectObject.self) { group in
      for _ in 0..<16 { group.addTask { try await document.resolve(root) } }
      var values = [PDFIndirectObject]()
      for try await value in group { values.append(value) }
      return values
    }
    #expect(values.count == 16)
    #expect(Set(values).count == 1)
    await document.close()
  }

  @Test
  func detectsShortSourceReadsAndDoesNotPoisonResolutionAfterCancellation() async throws {
    let encoded = try makeWriterDocument(version: .v1_7)
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(source: ShortReadSource(data: encoded.data))
    }

    let document = try await PDFDocument(source: PDFDataInputSource(encoded.data))
    let root = document.root
    let cancelled = Task { try await document.resolve(root) }
    cancelled.cancel()
    _ = try? await cancelled.value
    #expect(try await document.resolve(root).reference == root)
    await document.close()
  }

  @Test
  func resolvesObjectsAsOfHistoricalRevisions() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(incrementalFixture()))
    #expect(document.revisions.count == 2)
    let reference = try PDFObjectReference(objectNumber: 2, generationNumber: 0)
    let original = try await document.resolve(reference, in: document.revisions[0].identifier)
    let updated = try await document.resolve(reference)
    guard case .value(.string(let originalString)) = original.value,
      case .value(.string(let updatedString)) = updated.value
    else {
      Issue.record("Expected both historical values to be strings")
      return
    }
    #expect(originalString.bytes == Data("Original".utf8))
    #expect(updatedString.bytes == Data("Updated".utf8))
    #expect(original.definitionRevision == document.revisions[0].identifier)
    #expect(updated.definitionRevision == document.revisions[1].identifier)

    let added = try PDFObjectReference(objectNumber: 3, generationNumber: 0)
    await #expect(throws: PDFParsingError.unresolvedReference(added)) {
      _ = try await document.resolve(added, in: document.revisions[0].identifier)
    }
    #expect(try await document.resolve(added).value == .value(.integer(42)))

    let otherDocument = try await PDFDocument(source: PDFDataInputSource(incrementalFixture()))
    await #expect(throws: PDFParsingError.self) {
      _ = try await otherDocument.resolve(reference, in: document.revisions[0].identifier)
    }
    await otherDocument.close()
    await document.close()
  }

  private func makeWriterDocument(version: PDFVersion) throws -> PDFEncodedDocument {
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(version: version, compressionLevel: 0)
    )
    let catalog = try writer.reserveObject()
    let pages = try writer.reserveObject()
    let page = try writer.reserveObject()
    let contents = try writer.reserveObject()
    try writer.write(
      .dictionary(["Type": .name("Catalog"), "Pages": .reference(pages)]),
      to: catalog
    )
    try writer.write(
      .dictionary([
        "Type": .name("Pages"),
        "Count": .integer(1),
        "Kids": .array([.reference(page)]),
      ]),
      to: pages
    )
    try writer.write(
      .dictionary([
        "Type": .name("Page"),
        "Parent": .reference(pages),
        "Contents": .reference(contents),
      ]),
      to: page
    )
    try writer.writeStream(
      chunks: [Data("0 0 m 1 1 l S\n".utf8)],
      compressed: false,
      to: contents
    )
    return try writer.finish(root: catalog, pageCount: 1)
  }

  private func incrementalFixture() -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    let rootOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog /Pages 4 0 R /Value 2 0 R >>\nendobj\n".utf8))
    let originalValueOffset = data.count
    data.append(Data("2 0 obj\n(Original)\nendobj\n".utf8))
    let pagesOffset = data.count
    data.append(Data("4 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\n".utf8))
    let originalXRefOffset = data.count
    data.append(Data("xref\n0 5\n0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", rootOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", originalValueOffset).utf8))
    data.append(Data("0000000000 00000 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", pagesOffset).utf8))
    data.append(Data("trailer\n<< /Size 5 /Root 1 0 R >>\n".utf8))
    data.append(Data("startxref\n\(originalXRefOffset)\n%%EOF\n".utf8))

    let updatedValueOffset = data.count
    data.append(Data("2 0 obj\n(Updated)\nendobj\n".utf8))
    let addedValueOffset = data.count
    data.append(Data("3 0 obj\n42\nendobj\n".utf8))
    let updatedXRefOffset = data.count
    data.append(Data("xref\n2 2\n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", updatedValueOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", addedValueOffset).utf8))
    data.append(
      Data(
        ("trailer\n<< /Size 5 /Root 1 0 R /Prev \(originalXRefOffset) >>\n"
          + "startxref\n\(updatedXRefOffset)\n%%EOF\n").utf8
      )
    )
    return data
  }

  private func objectStreamFixture() -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    let rootOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog /Pages 5 0 R /Member 3 0 R >>\nendobj\n".utf8))
    let objectStreamOffset = data.count
    let objectStream = Data("3 0 << /Value 42 >>".utf8)
    data.append(
      Data(
        ("2 0 obj\n<< /Type /ObjStm /N 1 /First 4 /Length \(objectStream.count) >>\n"
          + "stream\n").utf8
      )
    )
    data.append(objectStream)
    data.append(Data("\nendstream\nendobj\n".utf8))
    let pagesOffset = data.count
    data.append(Data("5 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\n".utf8))
    let xrefOffset = data.count
    var entries = Data()
    appendEntry(type: 0, field2: 0, field3: 65_535, to: &entries)
    appendEntry(type: 1, field2: rootOffset, field3: 0, to: &entries)
    appendEntry(type: 1, field2: objectStreamOffset, field3: 0, to: &entries)
    appendEntry(type: 2, field2: 2, field3: 0, to: &entries)
    appendEntry(type: 0, field2: 0, field3: 0, to: &entries)
    appendEntry(type: 1, field2: pagesOffset, field3: 0, to: &entries)
    appendEntry(type: 1, field2: xrefOffset, field3: 0, to: &entries)
    data.append(
      Data(
        ("6 0 obj\n<< /Type /XRef /Size 7 /Root 1 0 R /W [1 4 2] "
          + "/Length \(entries.count) >>\nstream\n").utf8
      )
    )
    data.append(entries)
    data.append(Data("\nendstream\nendobj\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }

  private func cyclicLengthFixture() -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    var offsets = [0]
    offsets.append(data.count)
    data.append(Data("1 0 obj\n<< /Length 2 0 R >>\nstream\n\nendstream\nendobj\n".utf8))
    offsets.append(data.count)
    data.append(Data("2 0 obj\n<< /Length 1 0 R >>\nstream\n\nendstream\nendobj\n".utf8))
    offsets.append(data.count)
    data.append(Data("3 0 obj\n<< /Type /Catalog /Pages 4 0 R >>\nendobj\n".utf8))
    offsets.append(data.count)
    data.append(Data("4 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n0 5\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
      data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size 5 /Root 3 0 R >>\n".utf8))
    data.append(Data("startxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }

  private func streamWithoutTrailingLineEndingFixture() -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    let streamOffset = data.count
    data.append(Data("1 0 obj\n<< /Length 3 >>\nstream\n".utf8))
    data.append(contentsOf: [0x00, 0xFF, 0x0D])
    data.append(Data("endstream\nendobj\n".utf8))
    let rootOffset = data.count
    data.append(Data("2 0 obj\n<< /Type /Catalog /Pages 3 0 R >>\nendobj\n".utf8))
    let pagesOffset = data.count
    data.append(Data("3 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n0 4\n0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", streamOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", rootOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", pagesOffset).utf8))
    data.append(Data("trailer\n<< /Size 4 /Root 2 0 R >>\n".utf8))
    data.append(Data("startxref\n\(xrefOffset)\n%%EOF\n".utf8))
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

private struct ShortReadSource: PDFInputSource, Sendable {
  let data: Data

  func makeSession() async throws -> sending ShortReadSession {
    ShortReadSession(data: data)
  }
}

private actor ShortReadSession: PDFInputSourceSession {
  let data: Data

  init(data: Data) {
    self.data = data
  }

  func length() async throws -> Int64 { Int64(data.count) }

  func read(_ range: PDFSourceRange) async throws -> Data {
    let lower = Int(range.offset)
    let requested = data.subdata(in: lower..<(lower + range.length))
    return requested.isEmpty ? requested : requested.dropLast()
  }

  func close() async {}
}
