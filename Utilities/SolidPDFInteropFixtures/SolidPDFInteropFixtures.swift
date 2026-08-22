import Foundation
import SolidPDF
import SolidPDFParsingBenchmarkSupport

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
  }
}
