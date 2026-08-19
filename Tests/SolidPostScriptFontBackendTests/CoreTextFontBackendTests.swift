#if canImport(CoreText)
import SolidFont
import SolidPostScript
import SolidPostScriptCoreText
import Testing

@Suite("CoreText font backend")
struct CoreTextFontBackendTests {
  @Test("Provider resolves an installed face and exact glyph")
  func providerAndGlyph() async throws {
    let provider = CoreTextFontProvider()
    let names = try await provider.availableFontNames()
    var resolved: FontProviderFace?
    for name in names where resolved == nil {
      resolved = try await provider.resolve(FontResourceQuery(name: name, permitsSubstitution: false))
    }
    let face = try #require(resolved)
    let glyph = try await provider.glyph(.index(0), in: face)

    #expect(face.asset.format == .sfnt)
    #expect(glyph != nil)

    let session = CoreTextGraphicsFontEngine().makeSession(for: .letter)
    let font = GraphicsFontDescription(
      identifier: GraphicsFontIdentifier("coretext-test"),
      postScriptName: face.asset.descriptor.postScriptName,
      asset: face.asset
    )
    let preparedFont = try #require(try session.prepare(font))
    let description = GraphicsGlyphDescription(
      selector: .index(0),
      metrics: GraphicsGlyphMetrics(horizontalAdvance: GraphicsPoint(x: 0, y: 0)),
      program: .empty
    )
    #expect(try session.prepare(description, in: preparedFont) != nil)
  }

  @Test("Environment factory enables host font lookup")
  func environmentFactory() async throws {
    _ = try await Interpreter.execute(
      content: "/Helvetica findfont /FontType get",
      environment: .coreText()
    )
  }
}
#endif
