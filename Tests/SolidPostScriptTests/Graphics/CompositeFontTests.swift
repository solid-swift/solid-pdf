import Testing

@testable import SolidPostScript

@Suite struct CompositeFontTests {
  @Test(arguments: Array(2...9))
  func everyStandardMappingTypeSelectsTheExpectedDescendants(type: Int) async throws {
    let x: RealValue = try await Interpreter.result(content: try mappingProgram(for: type))
    #expect(abs(x.value - expectedAdvance(for: type)) < 1e-9)
  }

  @Test func typeOneIsNeitherAdvertisedNorAcceptedByTypeZeroFonts() async throws {
    let unavailable: BooleanValue = try await Interpreter.result(content: "1 /FMapType resourcestatus")
    #expect(unavailable.value == false)

    let findError: BooleanValue = try await Interpreter.result(
      content:
        "{ 1 /FMapType findresource } stopped clear $error /errorname get /undefinedresource eq $error /command get /findresource load eq and"
    )
    #expect(findError.value)

    let fontError: BooleanValue = try await Interpreter.result(content: Self.baseFonts + """
      { /Invalid 20 dict dup begin
          /FontType 0 def /FontMatrix matrix def /FontBBox [0 0 1 1] def
          /FMapType 1 def /Encoding [0] def /FDepVector [/Wide findfont] def
        end definefont
      } stopped clear
      $error /errorname get /invalidfont eq
      $error /command get /definefont load eq and
      """)
    #expect(fontError.value)
  }

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

  @Test(arguments: [2, 3, 5, 6, 7, 9])
  func incompleteVariableLengthMappingsRaiseRangecheck(type: Int) async throws {
    let error: NameValue = try await Interpreter.result(content: incompleteMappingProgram(for: type))
    #expect(error.value == "rangecheck")
  }

  @Test func mappingAndDescendantIndexesAreRangeCheckedAtUseTime() async throws {
    let mappingError: NameValue = try await Interpreter.result(content:
      compositeProgram(type: 2, input: "0241", catchesError: true)
    )
    #expect(mappingError.value == "rangecheck")

    let descendantError: NameValue = try await Interpreter.result(content: Self.baseFonts + """
      /Composite /Composite 20 dict dup begin
        /FontType 0 def /FontName /Composite def /FontMatrix matrix def /FontBBox [0 0 1 1] def
        /FMapType 2 def /Encoding [0] def /FDepVector [/Wide findfont] def
      end definefont def
      Composite /Encoding get 0 1 put
      Composite setfont 0 0 moveto { <0041> show } stopped clear $error /errorname get
      """)
    #expect(descendantError.value == "rangecheck")
  }

  @Test func compositeFontNestingBeyondFiveLevelsRaisesInvalidfont() async throws {
    var program = Self.baseFonts
    for level in 1...7 {
      let descendant = level == 1 ? "/Wide findfont" : "/Level\(level - 1) findfont"
      program += """
        /Level\(level) 20 dict dup begin
          /FontType 0 def /FontName /Level\(level) def /FontMatrix matrix def /FontBBox [0 0 1 1] def
          /FMapType 4 def /Encoding [0] def /FDepVector [\(descendant)] def
        end definefont pop
        """
    }
    program += "/Level7 findfont setfont 0 0 moveto { <41> show } stopped"

    let rejected: BooleanValue = try await Interpreter.result(content: program)
    #expect(rejected.value)
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

  private func mappingProgram(for type: Int) throws -> String {
    switch type {
    case 2:
      return compositeProgram(type: type, input: "00410141")
    case 3:
      return compositeProgram(type: type, input: "41ff0141")
    case 4:
      return compositeProgram(type: type, input: "41c1")
    case 5:
      return compositeProgram(type: type, input: "004100c1")
    case 6:
      return compositeProgram(type: type, input: "41c1", extraEntries: "/SubsVector <0080> def")
    case 7:
      return compositeProgram(
        type: type,
        input: "ffff0141",
        encoding: "/Encoding 258 array def 0 1 257 { Encoding exch 0 put } for Encoding 257 1 put"
      )
    case 8:
      return compositeProgram(type: type, input: "410e410f41")
    case 9:
      return Self.baseFonts + Self.descendantCMap + """
        /Mapped /DescendantMap [/Wide /Narrow] composefont pop
        /Mapped findfont 100 scalefont setfont 0 0 moveto <4142> show currentpoint pop
        """
    default:
      throw Error.invalidFont
    }
  }

  private func incompleteMappingProgram(for type: Int) -> String {
    switch type {
    case 2:
      compositeProgram(type: type, input: "00", catchesError: true)
    case 3:
      compositeProgram(type: type, input: "ff", catchesError: true)
    case 5:
      compositeProgram(type: type, input: "00", catchesError: true)
    case 6:
      compositeProgram(
        type: type,
        input: "41",
        extraEntries: "/SubsVector <010080> def",
        catchesError: true
      )
    case 7:
      compositeProgram(type: type, input: "ffff", catchesError: true)
    case 9:
      Self.baseFonts + Self.twoByteCMap + """
        /Mapped /TwoByteMap [/Wide] composefont pop
        /Mapped findfont setfont 0 0 moveto { <00> show } stopped clear $error /errorname get
        """
    default:
      preconditionFailure("Only variable-length FMapTypes have incomplete-code fixtures")
    }
  }

  private func compositeProgram(
    type: Int,
    input: String,
    encoding: String = "/Encoding [0 1] def",
    extraEntries: String = "",
    catchesError: Bool = false
  ) -> String {
    let paint = catchesError
      ? "{ <\(input)> show } stopped clear $error /errorname get"
      : "<\(input)> show currentpoint pop"
    return Self.baseFonts + """
      /Composite 20 dict dup begin
        /FontType 0 def /FontName /Composite def /FontMatrix matrix def /FontBBox [0 0 1 1] def
        /FMapType \(type) def \(encoding)
        /FDepVector [/Wide findfont /Narrow findfont] def
        \(extraEntries)
      end definefont pop
      /Composite findfont 100 scalefont setfont 0 0 moveto \(paint)
      """
  }

  private func expectedAdvance(for type: Int) -> Double {
    switch type {
    case 2: 90
    case 3: 90
    case 4: 90
    case 5: 90
    case 6: 90
    case 7: 30
    case 8: 150
    case 9: 90
    default: 0
    }
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

  private static let descendantCMap = """
    /CIDInit /ProcSet findresource begin
      20 dict begin begincmap
        /CMapType 1 def /CMapName /DescendantMap def /CIDSystemInfo [null] def
        1 begincodespacerange <00> <ff> endcodespacerange
        0 usefont 1 beginbfchar <41> /A endbfchar
        1 usefont 1 beginbfchar <42> /A endbfchar
        endcmap currentdict /DescendantMap exch /CMap defineresource pop
      end
    end
    """

  private static let twoByteCMap = """
    /CIDInit /ProcSet findresource begin
      20 dict begin begincmap
        /CMapType 1 def /CMapName /TwoByteMap def /CIDSystemInfo [null] def
        1 begincodespacerange <0000> <ffff> endcodespacerange
        0 usefont 1 beginbfchar <0041> /A endbfchar
        endcmap currentdict /TwoByteMap exch /CMap defineresource pop
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
