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

  @Test
  func createsIncrementalAndEncryptedFixtures() async throws {
    let incremental = try await PDFDocument(
      source: PDFDataInputSource(PDFParsingBenchmarkFixtures.incrementalDocument(revisionCount: 8))
    )
    #expect(incremental.revisions.count == 8)
    let value = try PDFObjectReference(objectNumber: 2, generationNumber: 0)
    #expect(try await incremental.resolve(value).value == .value(.integer(7)))
    await incremental.close()

    for fixture in [
      PDFParsingBenchmarkFixtures.r4RC4Document,
      PDFParsingBenchmarkFixtures.r6AESDocument,
    ] {
      let encrypted = try await PDFDocument(
        source: PDFDataInputSource(fixture),
        password: PDFPassword("user")
      )
      #expect(encrypted.security != nil)
      #expect(try await pageContent(in: encrypted) == Data("0 0 m 72 72 l S\n".utf8))
      await encrypted.close()
    }
  }

  private func pageContent<Source: PDFInputSource>(
    in document: PDFDocument<Source>
  ) async throws -> Data {
    guard case .value(.dictionary(let catalog)) = try await document.resolve(document.root).value,
      case .reference(let pagesReference) = catalog["Pages"],
      case .value(.dictionary(let pages)) = try await document.resolve(pagesReference).value,
      case .array(let kids) = pages["Kids"],
      case .reference(let pageReference) = kids.first,
      case .value(.dictionary(let page)) = try await document.resolve(pageReference).value,
      case .reference(let contentReference) = page["Contents"],
      case .stream(let stream) = try await document.resolve(contentReference).value
    else {
      throw PDFParsingError.malformed(.init(offset: 0, message: "Fixture page is malformed."))
    }
    return try await document.decodedBytes(of: stream)
  }
}
