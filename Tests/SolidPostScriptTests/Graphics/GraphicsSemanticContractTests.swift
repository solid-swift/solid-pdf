import Foundation
import Testing

@testable import SolidPostScript

@Suite struct GraphicsSemanticContractTests {
  @Test func checkedInManifestMatchesFrozenV1CaseInventory() throws {
    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)

    #expect(manifest.schemaVersion == 1)
    #expect(manifest.contractVersion == GraphicsSemanticContractVersion.current.rawValue)
    #expect(Set(manifest.operationCases.root) == ["state", "transform", "path", "clip", "paint", "page"])
    #expect(Set(manifest.operationCases.paint) == Set(Self.paintCases))
    #expect(Set(manifest.effectCases) == Set(Self.effectCases))
    #expect(manifest.compatibility.enumExpansion == "major-version")
    #expect(!manifest.compatibility.silentSemanticDefaults)
  }

  private static let paintCases = [
    "erasePage", "fill", "stroke", "fillRectangles", "strokeRectangles", "image",
    "userPathFill", "userPathStroke", "shading", "form", "text",
  ]

  private static let effectCases = [
    "fill", "stroke", "userPathFill", "userPathStroke", "erase", "fillRectangles",
    "strokeRectangles", "image", "shading", "form", "text",
  ]

  private var manifestURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Documentation/GraphicsSemanticContract.json")
  }

  private struct Manifest: Decodable {
    let schemaVersion: Int
    let contractVersion: Int
    let operationCases: OperationCases
    let effectCases: [String]
    let compatibility: Compatibility
  }

  private struct OperationCases: Decodable {
    let root: [String]
    let paint: [String]
  }

  private struct Compatibility: Decodable {
    let enumExpansion: String
    let silentSemanticDefaults: Bool
  }
}
