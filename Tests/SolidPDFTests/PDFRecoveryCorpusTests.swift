import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFRecoveryCorpusTests {
  @Test
  func manifestCoversRegistryAndRecoversEveryFixture() async throws {
    let directory = fixtureDirectory
    let manifest = try JSONDecoder().decode(
      Manifest.self,
      from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    )
    #expect(manifest.schemaVersion == 1)
    #expect(!manifest.corpusVersion.isEmpty)
    let identifiers = manifest.cases.map(\.id)
    #expect(Set(identifiers).count == identifiers.count)
    let registered = try Set(PDFRecoveryRegistry.builtIn.passes.map(\.descriptor.identifier))
    #expect(Set(manifest.cases.flatMap(\.passes)) == registered)

    for fixture in manifest.cases {
      let source = directory.appendingPathComponent(fixture.source)
      let data = try Data(contentsOf: source)
      #expect(Self.hexDigest(data) == fixture.sha256)
      await #expect(throws: PDFParsingError.self) {
        _ = try await PDFDocument(source: PDFDataInputSource(data))
      }
      let policy: PDFRecoveryPolicy = fixture.minimumPolicy == "compatible" ? .compatible : .structural
      let document = try await PDFDocument(
        source: PDFDataInputSource(data),
        options: .init(recovery: .init(policy: policy))
      )
      #expect(document.recoveryReport != nil)
      #expect(try await document.pageCount() == fixture.expectedPageCount)
      await document.close()
    }
  }

  private var fixtureDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PDF/Recovery", isDirectory: true)
  }

  private static func hexDigest(_ data: Data) -> String {
    PDFCrypto.sha256(data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct Manifest: Decodable {
  let schemaVersion: Int
  let corpusVersion: String
  let cases: [Fixture]
}

private struct Fixture: Decodable {
  let id: String
  let source: String
  let sha256: String
  let minimumPolicy: String
  let passes: [String]
  let expectedPageCount: Int
}
