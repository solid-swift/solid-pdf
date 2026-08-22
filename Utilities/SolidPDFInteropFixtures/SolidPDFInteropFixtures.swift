import Foundation
import SolidPDF
import SolidPDFParsingBenchmarkSupport
import SolidIO

@main
enum SolidPDFInteropFixtures {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      FileHandle.standardError.write(Data("usage: SolidPDFInteropFixtures OUTPUT_DIRECTORY\n".utf8))
      Foundation.exit(64)
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try PDFParsingBenchmarkFixtures.document(version: .v1_7)
      .write(to: directory.appendingPathComponent("writer-1.7.pdf"))
    try PDFParsingBenchmarkFixtures.document(version: .v2_0)
      .write(to: directory.appendingPathComponent("writer-2.0.pdf"))
    try PDFParsingBenchmarkFixtures.objectStreamDocument(containedObjectCount: 8)
      .write(to: directory.appendingPathComponent("object-stream.pdf"))
    let expected = Data((0..<65_537).map { UInt8(truncatingIfNeeded: $0 * 37) })
    try expected.write(to: directory.appendingPathComponent("mixed-filter.expected"))
    try mixedFilterDocument(expected)
      .write(to: directory.appendingPathComponent("mixed-filter.pdf"))
  }

  private static func mixedFilterDocument(_ decoded: Data) throws -> Data {
    let flate = FlateEncoder()
    let compressed = try flate.process(input: decoded).output + (try flate.finish() ?? Data())
    let ascii85 = ASCII85Encoder()
    let encoded = try ascii85.process(input: compressed).output + (try ascii85.finish() ?? Data())
    var writer = try PDFDocumentWriter(sink: PDFDataOutputSink(), options: .init(version: .v1_7))
    let catalog = try writer.reserveObject()
    let pages = try writer.reserveObject()
    let stream = try writer.reserveObject()
    try writer.write(
      .dictionary([
        "Type": .name("Catalog"),
        "Pages": .reference(pages),
        "Stream": .reference(stream),
      ]),
      to: catalog
    )
    try writer.write(
      .dictionary(["Type": .name("Pages"), "Count": .integer(0), "Kids": .array([])]),
      to: pages
    )
    try writer.writeStream(
      dictionary: [
        "Filter": .array([.name("ASCII85Decode"), .name("FlateDecode")]),
        "DecodeParms": .array([.null, .null]),
      ],
      chunks: [encoded],
      compressed: false,
      to: stream
    )
    return try writer.finish(root: catalog, pageCount: 0).data
  }
}
