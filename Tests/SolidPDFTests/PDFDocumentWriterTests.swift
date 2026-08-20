import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFDocumentWriterTests {
  @Test(arguments: PDFVersion.allCases)
  func writesDeterministicDocumentWithForwardReferences(_ version: PDFVersion) throws {
    let first = try makeDocument(version: version)
    let second = try makeDocument(version: version)
    #expect(first.data == second.data)
    #expect(first.version == version)
    #expect(first.pageCount == 1)
    #expect(first.data.starts(with: Data("%PDF-\(version.rawValue)".utf8)))
    #expect(first.data.containsASCII("/Type /Catalog"))
    #expect(first.data.containsASCII("/Length 5 0 R"))
    if version == .v1_7 {
      #expect(first.data.containsASCII("xref\n0 "))
      #expect(first.data.containsASCII("trailer\n"))
    } else {
      #expect(first.data.containsASCII("/Type /XRef"))
      #expect(!first.data.containsASCII("trailer\n"))
    }
  }

  @Test
  func serializesNamesStringsAndFiniteNumbersCanonically() throws {
    let serializer = PDFObjectSerializer(limits: .init())
    let value = PDFObject.dictionary([
      PDFName(bytes: Data([0x41, 0x20, 0x23])): .string(
        PDFString(bytes: Data([0, 0xFF]), representation: .automatic)
      ),
      "Literal": .string(PDFString("a(b)\\c\n", representation: .literal)),
      "Tiny": .real(1e-7),
    ])
    let result = try serializer.serialize(value)
    #expect(result.containsASCII("/A#20#23 <00FF>"))
    #expect(result.containsASCII("/Literal (a\\(b\\)\\\\c\\n)"))
    #expect(result.containsASCII("/Tiny 0.0000001"))
    #expect(throws: PDFError.invalidObject) {
      try serializer.serialize(.real(.infinity))
    }
  }

  @Test
  func unresolvedReservationFailsWithoutPublishing() throws {
    var writer = try PDFDocumentWriter(sink: PDFDataOutputSink())
    let root = try writer.reserveObject()
    _ = try writer.reserveObject()
    try writer.write(.dictionary(["Type": .name("Catalog")]), to: root)
    do {
      _ = try writer.finish(root: root, pageCount: 0)
      Issue.record("Expected the unresolved reservation to fail")
    } catch {
      #expect(error as? PDFError == .unresolvedReference(PDFObjectReference(objectNumber: 2)))
    }
  }

  @Test
  func enforcesStreamAndOutputLimits() throws {
    let limits = PDFWritingLimits(
      maximumObjectCount: 16,
      maximumObjectNesting: 8,
      maximumStreamBytes: 3,
      maximumOutputBytes: 1_024,
      maximumTemporaryBytes: 1_024
    )
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(limits: limits)
    )
    let stream = try writer.reserveObject()
    #expect(throws: PDFError.limitExceeded) {
      try writer.writeStream(chunks: [Data([1, 2, 3, 4])], to: stream)
    }
  }

  @Test
  func atomicSinkPublishesOnlyOnFinish() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("document.pdf")

    var writer = try PDFDocumentWriter(
      sink: PDFAtomicFileOutputSink(destination: destination),
      options: .init(version: .v1_7)
    )
    let root = try writer.reserveObject()
    try writer.write(.dictionary(["Type": .name("Catalog")]), to: root)
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    let output = try writer.finish(root: root, pageCount: 0)
    #expect(output == destination)
    #expect(try Data(contentsOf: output).containsASCII("%PDF-1.7"))
  }
}

private func makeDocument(version: PDFVersion) throws -> PDFEncodedDocument {
  var writer = try PDFDocumentWriter(
    sink: PDFDataOutputSink(),
    options: .init(version: version, compressionLevel: 0)
  )
  let catalog = try writer.reserveObject()
  let pages = try writer.reserveObject()
  let page = try writer.reserveObject()
  let contents = try writer.reserveObject()
  try writer.write(
    .dictionary([
      "Type": .name("Catalog"),
      "Pages": .reference(pages),
    ]),
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
      "MediaBox": .array([.integer(0), .integer(0), .integer(100), .integer(100)]),
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

private extension Data {
  func containsASCII(_ string: String) -> Bool {
    range(of: Data(string.utf8)) != nil
  }
}
