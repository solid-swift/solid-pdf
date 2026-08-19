import Testing

@testable import SolidPostScript

@Suite struct CompositeFontTests {
  @Test func eightByEightMappingSelectsDescendantFonts() async throws {
    let context = try await Interpreter.execute(content: Self.baseFonts + """
      /Composite 20 dict dup begin
        /FontType 0 def /FontName /Composite def /FontMatrix matrix def /FontBBox [0 0 1 1] def
        /FMapType 2 def /Encoding [0 1] def
        /FDepVector [/Wide findfont 100 scalefont /Narrow findfont 100 scalefont] def
      end definefont pop
      /Composite findfont setfont 10 20 moveto <00410141> show currentpoint
      """)
    let values = try await context.results()
    #expect(try values[1].value(as: RealValue.self).value == 100)
    #expect(try values[0].value(as: RealValue.self).value == 20)
  }

  @Test func incompleteCompositeCodesRaiseRangecheck() async throws {
    let context = try await Interpreter.execute(content: Self.baseFonts + """
      /Composite 20 dict dup begin
        /FontType 0 def /FontMatrix matrix def /FontBBox [0 0 1 1] def
        /FMapType 2 def /Encoding [0] def /FDepVector [/Wide findfont] def
      end definefont pop
      /Composite findfont setfont 0 0 moveto
      { <00> show } stopped $error /errorname get
      """)
    let values = try await context.results()
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: NameValue.self).value == "rangecheck")
  }

  @Test func cidInitBuildsCMapsUsedByComposefont() async throws {
    let context = try await Interpreter.execute(content: Self.baseFonts + Self.cmap + """
      /Composed /TestMap [/Wide] composefont pop
      /Composed findfont 100 scalefont setfont 10 20 moveto (A) show currentpoint
      """)
    let values = try await context.results()
    #expect(try values[1].value(as: RealValue.self).value == 70)
    #expect(try values[0].value(as: RealValue.self).value == 20)
  }

  @Test func cidFontTypeOneBuildGlyphReceivesTheMappedCID() async throws {
    let context = try await Interpreter.execute(content: Self.cidFont + Self.cidCMap + """
      /CIDComposite /CIDMap [/TestCID] composefont pop
      /CIDComposite findfont 100 scalefont setfont 0 0 moveto (A) show currentpoint
      """)
    let values = try await context.results()
    #expect(try values[1].value(as: RealValue.self).value == 50)
    #expect(try values[0].value(as: RealValue.self).value == 0)
  }

  @Test func bitmapFontProcSetAddsAndRemovesPinnedGlyphs() async throws {
    let context = try await Interpreter.execute(content: Self.bitmapFont + Self.cidCMap + """
      /BitmapFontInit /ProcSet findresource begin
        [500 0 0 0 1 1] <80> 5 /Bitmap /CIDFont findresource addglyph
      end
      /BitmapComposite /CIDMap [/Bitmap] composefont pop
      /BitmapComposite findfont 100 scalefont setfont 0 0 moveto (A) show currentpoint
      /BitmapFontInit /ProcSet findresource begin
        5 5 /Bitmap /CIDFont findresource removeglyphs
      end
      0 0 moveto (A) show currentpoint
      """)
    let values = try await context.results()
    #expect(try values[3].value(as: RealValue.self).value == 50)
    #expect(try values[2].value(as: RealValue.self).value == 0)
    #expect(try values[1].value(as: RealValue.self).value == 0)
    #expect(try values[0].value(as: RealValue.self).value == 0)
  }

  private static let baseFonts = """
    /Wide 20 dict dup begin
      /FontType 3 def /FontMatrix [.001 0 0 .001 0 0] def /FontBBox [0 0 600 700] def
      /Encoding StandardEncoding def /BuildGlyph { pop pop 600 0 setcharwidth } bind def
    end definefont pop
    /Narrow 20 dict dup begin
      /FontType 3 def /FontMatrix [.001 0 0 .001 0 0] def /FontBBox [0 0 300 700] def
      /Encoding StandardEncoding def /BuildGlyph { pop pop 300 0 setcharwidth } bind def
    end definefont pop
    """

  private static let cmap = """
    /CIDInit /ProcSet findresource begin
      20 dict begin begincmap
        /CMapType 1 def /CMapName /TestMap def /CIDSystemInfo [null] def
        1 begincodespacerange <00> <ff> endcodespacerange
        0 usefont 1 beginbfchar <41> /A endbfchar
        endcmap currentdict /TestMap exch /CMap defineresource pop
      end
    end
    """

  private static let cidFont = """
    /TestCID 20 dict dup begin
      /CIDFontType 1 def /FontType 10 def /CIDFontName /TestCID def
      /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def
      /CIDCount 32 def /FontMatrix [.001 0 0 .001 0 0] def /FontBBox [0 0 500 700] def
      /BuildGlyph { exch pop 5 eq { 500 0 setcharwidth } { 0 0 setcharwidth } ifelse } bind def
    end /CIDFont defineresource pop
    """

  private static let cidCMap = """
    /CIDInit /ProcSet findresource begin
      20 dict begin begincmap
        /CMapType 1 def /CMapName /CIDMap def
        /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def
        1 begincodespacerange <00> <ff> endcodespacerange
        0 usefont 1 begincidchar <41> 5 endcidchar
        endcmap currentdict /CIDMap exch /CMap defineresource pop
      end
    end
    """

  private static let bitmapFont = """
    /Bitmap 20 dict dup begin
      /CIDFontType 4 def /FontType 32 def /CIDFontName /Bitmap def
      /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def
      /CIDCount 32 def /FontMatrix [.001 0 0 .001 0 0] def /FontBBox [0 0 500 700] def
      /GlyphDirectory 1 dict def
    end /CIDFont defineresource pop
    """
}
