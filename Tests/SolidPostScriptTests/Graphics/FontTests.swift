import Testing

@testable import SolidPostScript

@Suite struct FontTests {
  @Test func standardEncodingsAreSharedResources() async throws {
    let context = try await Interpreter.execute(content: """
      StandardEncoding /StandardEncoding /Encoding findresource eq
      ISOLatin1Encoding /ISOLatin1Encoding /Encoding findresource eq
      FontDirectory type /dicttype eq
      GlobalFontDirectory SharedFontDirectory eq
      """)
    let values = try await context.results()
    for value in values {
      #expect(try value.value(as: BooleanValue.self).value)
    }
  }

  @Test func defineFindAndUndefineFontSynchronizeDirectories() async throws {
    let context = try await Interpreter.execute(content: """
      /F 10 dict dup begin
        /FontType 3 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 1000 1000] def /Encoding StandardEncoding def
        /BuildGlyph { pop pop 0 0 setcharwidth } bind def
      end definefont pop
      FontDirectory /F known
      /F findfont FontDirectory /F get eq
      /F undefinefont FontDirectory /F known
      """)
    let values = try await context.results()
    #expect(try values[2].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: BooleanValue.self).value == false)
  }

  @Test func type3TextUsesCacheMetricsAndAdvancesCurrentPoint() async throws {
    let context = try await Interpreter.execute(content: Self.type3Font + """
      /F findfont 100 scalefont setfont
      10 20 moveto (AA) show currentpoint
      (AAA) stringwidth
      """)
    let values = try await context.results()
    #expect(try values[3].value(as: RealValue.self).value == 130)
    #expect(try values[2].value(as: RealValue.self).value == 20)
    #expect(try values[1].value(as: RealValue.self).value == 180)
    #expect(try values[0].value(as: RealValue.self).value == 0)
  }

  @Test func type3TextIsRetainedAsASemanticRun() async throws {
    let result = try await Interpreter.render(
      content: Self.type3Font + """
        /F findfont 100 scalefont setfont 20 20 moveto (A) show showpage
        """,
      to: RecordingGraphicsTarget()
    )
    let page = try #require(result.output.pages.first)
    guard case .text(let run, _) = try #require(page.effects.first) else {
      Issue.record("Expected a semantic text effect")
      return
    }
    #expect(run.glyphs.count == 1)
    #expect(run.glyphs[0].advance.x == 60)
    guard case .displayList(let list) = run.glyphs[0].glyph.program else {
      Issue.record("Expected a captured Type 3 display list")
      return
    }
    #expect(!list.effects.isEmpty)
  }

  @Test func cshowMapsWithoutPaintingOrRequiringACurrentPoint() async throws {
    let context = try await Interpreter.execute(content: Self.type3Font + """
      /F findfont 100 scalefont setfont
      /sum 0 def
      { add add sum add /sum exch def } (AA) cshow
      sum currentfont /FontName get
      """)
    let values = try await context.results()
    #expect(try values[1].value(as: RealValue.self).value == 250)
    #expect(try values[0].value(as: NameValue.self).value == "F")
  }

  @Test func kshowInvokesTheProcedureBetweenRepeatedCharacters() async throws {
    let context = try await Interpreter.execute(content: Self.type3Font + """
      /F findfont 100 scalefont setfont
      /callbacks 0 def 10 20 moveto
      { pop pop /callbacks callbacks 1 add def } (AAA) kshow
      callbacks currentpoint
      """)
    let values = try await context.results()
    #expect(try values[2].value(as: IntegerValue.self).value == 2)
    #expect(try values[1].value(as: RealValue.self).value == 190)
    #expect(try values[0].value(as: RealValue.self).value == 20)
  }

  @Test func cacheCompatibilityOperatorsShareInterpreterParameters() async throws {
    let context = try await Interpreter.execute(content: """
      123 setcachelimit currentcacheparams
      """)
    let values = try await context.results()
    #expect(try values[0].value(as: IntegerValue.self).value == 123)
    #expect(try values[1].value(as: IntegerValue.self).value == 0)
    #expect(try values[2].value(as: IntegerValue.self).value == Int32(FontGlyphCache.maximumBytes))
    #expect(values[3].type == .mark)
  }

  private static let type3Font = """
    /F 20 dict dup begin
      /FontType 3 def
      /FontMatrix [0.001 0 0 0.001 0 0] def
      /FontBBox [0 0 600 700] def
      /Encoding StandardEncoding def
      /CharProcs 2 dict dup begin
        /.notdef { 0 0 setcharwidth } bind def
        /A {
          600 0 0 0 600 700 setcachedevice
          0 0 moveto 300 700 lineto 600 0 lineto closepath fill
        } bind def
      end def
      /BuildGlyph { exch begin CharProcs exch get exec end } bind def
    end
    /F exch definefont pop
    """
}
