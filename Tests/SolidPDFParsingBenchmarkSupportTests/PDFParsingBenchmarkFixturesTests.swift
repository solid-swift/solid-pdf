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
}
