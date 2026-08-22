import Foundation
import SolidPDF
import SolidPDFParsingBenchmarkSupport
import SolidIO

@main
enum SolidPDFInteropFixtures {
  static func main() async throws {
    switch CommandLine.arguments.dropFirst().first {
    case "create":
      guard CommandLine.arguments.count == 3 else { usage() }
      try createFixtures(in: CommandLine.arguments[2])
    case "verify-security":
      guard CommandLine.arguments.count == 4 else { usage() }
      try await verifySecurityFixture(
        at: CommandLine.arguments[2],
        password: CommandLine.arguments[3]
      )
    case let directory? where CommandLine.arguments.count == 2:
      try createFixtures(in: directory)
    default:
      usage()
    }
  }

  private static func createFixtures(in path: String) throws {
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try PDFParsingBenchmarkFixtures.document(version: .v1_7)
      .write(to: directory.appendingPathComponent("writer-1.7.pdf"))
    try PDFParsingBenchmarkFixtures.document(version: .v2_0)
      .write(to: directory.appendingPathComponent("writer-2.0.pdf"))
    try PDFParsingBenchmarkFixtures.objectStreamDocument(containedObjectCount: 8)
      .write(to: directory.appendingPathComponent("object-stream.pdf"))
    try PDFParsingBenchmarkFixtures.pageTreeDocument(pageCount: 64, branchSize: 8)
      .write(to: directory.appendingPathComponent("page-tree.pdf"))
    let expected = Data((0..<65_537).map { UInt8(truncatingIfNeeded: $0 * 37) })
    try expected.write(to: directory.appendingPathComponent("mixed-filter.expected"))
    try mixedFilterDocument(expected)
      .write(to: directory.appendingPathComponent("mixed-filter.pdf"))
  }

  private static func verifySecurityFixture(at path: String, password: String) async throws {
    let document = try await PDFDocument(
      source: PDFFileInputSource(url: URL(fileURLWithPath: path)),
      password: PDFPassword(password)
    )
    defer { Task { await document.close() } }
    guard document.security != nil else {
      throw PDFParsingError.malformed(
        .init(offset: 0, message: "The security interoperability fixture is unencrypted.")
      )
    }
    let catalog = try await document.resolve(document.root)
    guard case .value(.dictionary(let catalogDictionary)) = catalog.value,
      case .reference(let pagesReference) = catalogDictionary["Pages"],
      case .value(.dictionary(let pagesDictionary)) = try await document.resolve(pagesReference).value,
      case .array(let kids) = pagesDictionary["Kids"],
      case .reference(let pageReference) = kids.first,
      case .value(.dictionary(let pageDictionary)) = try await document.resolve(pageReference).value,
      case .reference(let contentReference) = pageDictionary["Contents"],
      case .stream(let stream) = try await document.resolve(contentReference).value
    else {
      throw PDFParsingError.malformed(
        .init(offset: 0, message: "The security interoperability page structure is malformed.")
      )
    }
    guard try await document.decodedBytes(of: stream) == Data("0 0 m 72 72 l S\n".utf8) else {
      throw PDFParsingError.malformed(
        .init(offset: 0, message: "The encrypted page stream did not decode exactly.")
      )
    }
    await document.close()
  }

  private static func usage() -> Never {
    FileHandle.standardError.write(
      Data(
        ("usage: SolidPDFInteropFixtures [create] OUTPUT_DIRECTORY\n"
          + "       SolidPDFInteropFixtures verify-security INPUT_PDF PASSWORD\n").utf8
      )
    )
    Foundation.exit(64)
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
