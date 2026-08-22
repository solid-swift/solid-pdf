import Foundation
import SolidPDF
import SolidPDFParsingBenchmarkSupport
import Testing

@Suite
struct PDFParsingBenchmarkFixturesTests {
  @Test(arguments: PDFVersion.allCases)
  func writerFixturesOpenAndResolveTheirCatalog(_ version: PDFVersion) async throws {
    let data = try PDFParsingBenchmarkFixtures.document(
      version: version,
      additionalObjectCount: 32
    )
    let document = try await PDFDocument(source: PDFDataInputSource(data))
    let root = try await document.resolve(document.root)
    #expect(root.reference.objectNumber == 1)
    await document.close()
  }

  @Test
  func objectStreamFixtureResolvesItsLastMember() async throws {
    let data = PDFParsingBenchmarkFixtures.objectStreamDocument(containedObjectCount: 32)
    let document = try await PDFDocument(source: PDFDataInputSource(data))
    let reference = try PDFObjectReference(objectNumber: 35, generationNumber: 0)
    let object = try await document.resolve(reference)
    #expect(object.reference == reference)
    #expect(object.provenance == .objectStream(
      container: try PDFObjectReference(objectNumber: 3, generationNumber: 0),
      index: 31
    ))
    await document.close()
  }


  @Test
  func compressedStreamFixtureDecodesItsPayload() async throws {
    let expected = Data(repeating: 0xA5, count: 65_537)
    let data = try PDFParsingBenchmarkFixtures.streamDocument(bytes: expected, compressed: true)
    let document = try await PDFDocument(source: PDFDataInputSource(data))
    let root = try await document.resolve(document.root)
    guard case .value(.dictionary(let dictionary)) = root.value,
      case .reference(let reference) = dictionary["Stream"],
      case .stream(let stream) = try await document.resolve(reference).value
    else {
      Issue.record("Expected the benchmark stream")
      return
    }
    #expect(try await document.decodedBytes(of: stream) == expected)
    await document.close()
  }
}
