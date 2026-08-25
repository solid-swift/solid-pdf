import Foundation
import Testing

@testable import SolidPostScript

@Suite struct GraphicsSemanticContractTests {
  @Test func checkedInManifestMatchesCurrentCaseInventory() throws {
    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)

    #expect(manifest.schemaVersion == 1)
    #expect(manifest.contractVersion == GraphicsSemanticContractVersion.current.rawValue)
    #expect(Set(manifest.operationCases.root) == ["state", "transform", "path", "clip", "paint", "content", "page"])
    #expect(Set(manifest.operationCases.paint) == Set(Self.paintCases))
    #expect(Set(manifest.effectCases) == Set(Self.effectCases))
    #expect(manifest.compatibility.enumExpansion == "major-version")
    #expect(!manifest.compatibility.silentSemanticDefaults)
  }

  @Test func textContractPreservesIndependentStyleAndSubstitutionEvidence() {
    let fill = GraphicsTextPaint(
      paint: .deviceRGB(red: 0.1, green: 0.2, blue: 0.3),
      colorSpace: .deviceRGB,
      components: [0.1, 0.2, 0.3]
    )
    let stroke = GraphicsTextPaint(
      paint: .deviceCMYK(cyan: 0.2, magenta: 0.3, yellow: 0.4, black: 0.1),
      colorSpace: .deviceCMYK,
      components: [0.2, 0.3, 0.4, 0.1],
      overprint: true
    )
    let font = GraphicsFontDescription(
      identifier: .init("pdf-font"),
      substitution: .init(
        requestedName: "Helvetica",
        resolvedName: "LiberationSans",
        providerIdentifier: "fixture"
      )
    )
    let run = GraphicsGlyphRun(
      rootFont: font,
      glyphs: [],
      renderingMode: .fillStrokeClip,
      style: .init(fill: fill, stroke: stroke)
    )

    #expect(GraphicsSemanticContractVersion.current == .v4)
    #expect(run.renderingMode.fills)
    #expect(run.renderingMode.strokes)
    #expect(run.renderingMode.clips)
    #expect(run.style?.stroke.overprint == true)
    #expect(run.rootFont.substitution?.requestedName == "Helvetica")
  }

  private static let paintCases = [
    "erasePage", "fill", "stroke", "fillAndStroke", "fillRectangles", "strokeRectangles", "image",
    "userPathFill", "userPathStroke", "shading", "form", "transparencyGroup", "text",
  ]

  private static let effectCases = [
    "fill", "stroke", "fillAndStroke", "userPathFill", "userPathStroke", "erase", "fillRectangles",
    "strokeRectangles", "image", "shading", "form", "transparencyGroup", "text", "markedContent",
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
