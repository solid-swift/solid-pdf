import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFIncrementalWriterTests {
  @Test(arguments: [PDFVersion.v1_7, .v2_0])
  func appendsParseableRevisionAndPreservesOriginalPrefix(_ version: PDFVersion) async throws {
    let original = try baseDocument(version: version)
    let source = try await PDFDocument(source: PDFDataInputSource(original.data))
    let root = source.root
    let encoded = try PDFIncrementalWriter(
      original: original.data,
      revision: source.latestRevision,
      objects: [
        root: .value(.dictionary([
          "Type": .name("Catalog"),
          "Pages": .reference(PDFObjectReference(objectNumber: 2, generationNumber: 0)),
          "Updated": .boolean(true),
        ]))
      ],
      limits: .init()
    ).encode()

    #expect(encoded.data.prefix(original.data.count) == original.data)
    #expect(encoded.appendedByteCount == encoded.data.count - original.data.count)
    #expect(encoded.representation == (version == .v1_7 ? .classic : .stream))

    let updated = try await PDFDocument(source: PDFDataInputSource(encoded.data))
    #expect(updated.revisions.count == 2)
    let object = try await updated.resolve(root)
    guard case .value(.dictionary(let dictionary)) = object.value else {
      Issue.record("Expected the updated catalog dictionary")
      return
    }
    #expect(dictionary["Updated"] == .boolean(true))
    await updated.close()
    await source.close()
  }

  @Test
  func enforcesAppendedByteLimitBeforePublication() async throws {
    let original = try baseDocument(version: .v1_7)
    let document = try await PDFDocument(source: PDFDataInputSource(original.data))
    let limits = PDFIncrementalWritingLimits(maximumAppendedBytes: 8)
    #expect(throws: PDFIncrementalUpdateError.limitExceeded) {
      try PDFIncrementalWriter(
        original: original.data,
        revision: document.latestRevision,
        objects: [document.root: .value(.dictionary(["Type": .name("Catalog")]))],
        limits: limits
      ).encode()
    }
    await document.close()
  }

  private func baseDocument(version: PDFVersion) throws -> PDFEncodedDocument {
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(version: version, compressionLevel: 0)
    )
    let catalog = try writer.reserveObject()
    let pages = try writer.reserveObject()
    try writer.write(
      .dictionary(["Type": .name("Catalog"), "Pages": .reference(pages)]),
      to: catalog
    )
    try writer.write(
      .dictionary(["Type": .name("Pages"), "Count": .integer(0), "Kids": .array([])]),
      to: pages
    )
    return try writer.finish(root: catalog, pageCount: 0)
  }
}
