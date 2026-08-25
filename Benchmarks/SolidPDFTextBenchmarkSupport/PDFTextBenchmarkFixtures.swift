import Foundation
import SolidFont
import SolidPostScript

/// Deterministic PDF inputs and a portable font provider for text benchmarks.
public enum PDFTextBenchmarkFixtures {
  /// Creates a simple-font page containing one long `Tj` operation.
  public static func simpleRun(glyphCount: Int = 10_000) -> Data {
    document(
      content: "BT /F1 10 Tf (\(String(repeating: "A", count: glyphCount))) Tj ET",
      resources: simpleResources
    )
  }

  /// Creates a simple-font page containing one long `TJ` operation.
  public static func adjustedRun(glyphCount: Int = 10_000) -> Data {
    let pairs = Array(repeating: "(A) -25", count: glyphCount).joined(separator: " ")
    return document(content: "BT /F1 10 Tf [\(pairs)] TJ ET", resources: simpleResources)
  }

  /// Creates a vertical Identity-V CID run.
  public static func verticalRun(glyphCount: Int = 5_000) -> Data {
    let codes = String(repeating: "002a", count: glyphCount)
    let resources = """
      << /Font << /F0 << /Type /Font /Subtype /Type0 /BaseFont /SyntheticCID /Encoding /Identity-V
        /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /SyntheticCID
          /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>
          /DW2 [880 -1000] /W2 [42 [-1200 400 900]] /CIDToGIDMap /Identity >>] >> >> >>
      """
    return document(content: "BT /F0 10 Tf <\(codes)> Tj ET", resources: resources)
  }

  /// Creates repeated Type 3 glyphs that exercise the display-list cache.
  public static func type3Run(glyphCount: Int = 2_000) -> Data {
    let procedure = stream("500 0 0 0 500 700 d1 0 0 500 700 re f")
    let resources = """
      << /Font << /F3 << /Type /Font /Subtype /Type3
        /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0]
        /CharProcs << /A 5 0 R >> /Encoding << /Differences [65 /A] >>
        /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >> >> >>
      """
    return document(
      content: "BT /F3 10 Tf (\(String(repeating: "A", count: glyphCount))) Tj ET",
      resources: resources,
      additionalObjects: [procedure]
    )
  }

  /// A provider that deterministically realizes benchmark glyphs without host discovery.
  public struct FontProvider: FontResourceProvider {
    /// Stable provider identifier.
    public let identifier = "benchmarks.pdf-text"

    /// Creates the provider.
    public init() {}

    /// Returns the fixture font names.
    public func availableFontNames() async throws -> [String] { ["Synthetic", "SyntheticCID"] }

    /// Resolves an exact fixture face.
    public func resolve(_ query: FontResourceQuery) async throws -> FontProviderFace? {
      guard query.name == "Synthetic" || query.name == "SyntheticCID" else { return nil }
      let descriptor = try FontDescriptor(postScriptName: query.name, unitsPerEm: 1_000)
      return FontProviderFace(
        providerIdentifier: identifier,
        faceKey: query.name,
        asset: try FontAsset(descriptor: descriptor, format: .type1, data: Data("fixture".utf8))
      )
    }

    /// Accepts the fixture Identity CID collection.
    public func isCompatible(with systemInfo: FontCIDSystemInfo, face: FontProviderFace) async throws -> Bool {
      systemInfo.registry == "Adobe" && systemInfo.ordering == "Identity"
    }

    /// Returns one reusable rectangular outline.
    public func glyph(_ selector: FontGlyphSelector, in face: FontProviderFace) async throws -> FontGlyph? {
      FontGlyph(
        selector: selector,
        metrics: FontGlyphMetrics(
          horizontalAdvance: FontPoint(x: 500, y: 0),
          bounds: FontBounds(minimumX: 0, minimumY: 0, maximumX: 500, maximumY: 700)
        ),
        program: .outline(FontOutline(elements: [
          .move(FontPoint(x: 0, y: 0)),
          .line(FontPoint(x: 500, y: 0)),
          .line(FontPoint(x: 500, y: 700)),
          .line(FontPoint(x: 0, y: 700)),
          .close,
        ])),
        resolvedGlyphIndex: 1
      )
    }
  }

  private static let simpleResources = """
    << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
      /FirstChar 65 /LastChar 65 /Widths [600] /Encoding /WinAnsiEncoding >> >> >>
    """

  private static func stream(_ content: String) -> Data {
    Data("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream".utf8)
  }

  private static func document(
    content: String,
    resources: String,
    additionalObjects: [Data] = []
  ) -> Data {
    var objects = [
      Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
      Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
      Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources \(resources) /Contents 4 0 R >>".utf8),
      stream(content),
    ]
    objects.append(contentsOf: additionalObjects)
    var data = Data("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n".utf8))
      data.append(object)
      data.append(Data("\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}
