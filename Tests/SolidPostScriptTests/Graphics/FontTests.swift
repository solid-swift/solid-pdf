import SolidFont
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

  @Test func setcharwidthGlyphsAreRebuiltInsteadOfCached() async throws {
    let context = try await Interpreter.execute(content: """
      /builds 0 def
      /F 12 dict dup begin
        /FontType 3 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 600 700] def /Encoding StandardEncoding def
        /BuildGlyph { pop pop /builds builds 1 add store 600 0 setcharwidth } bind def
      end definefont pop
      /F findfont 100 scalefont setfont 0 0 moveto (A) show (A) show builds
      """)
    let values = try await context.results()
    let builds = try values[0].value(as: IntegerValue.self)
    #expect(builds.value == 2)
  }

  @Test func setcachedeviceGlyphsUseTheRealizationCache() async throws {
    let context = try await Interpreter.execute(content: """
      /builds 0 def
      /F 12 dict dup begin
        /FontType 3 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 600 700] def /Encoding StandardEncoding def
        /BuildGlyph {
          pop pop /builds builds 1 add store
          600 0 0 0 600 700 setcachedevice
        } bind def
      end definefont pop
      /F findfont 100 scalefont setfont 0 0 moveto (AA) show builds
      """)
    let values = try await context.results()
    let builds = try values[0].value(as: IntegerValue.self)
    #expect(builds.value == 1)
  }

  @Test func type3MetricsMustPrecedeGraphicsOperations() async throws {
    let context = try await Interpreter.execute(content: """
      /F 12 dict dup begin
        /FontType 3 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 600 700] def /Encoding StandardEncoding def
        /BuildGlyph { pop pop 0 0 moveto 600 0 setcharwidth } bind def
      end definefont pop
      /F findfont 100 scalefont setfont 0 0 moveto { (A) show } stopped
      $error /errorname get /undefined eq $error /command get /moveto load eq
      """)
    let values = try await context.results()
    #expect(try values[2].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: BooleanValue.self).value)
  }

  @Test func metricsDictionaryOverridesDecodedCharStringWidth() async throws {
    let context = try await Interpreter.execute(content: """
      /F 16 dict dup begin
        /FontType 1 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 600 700] def /Encoding StandardEncoding def
        /Private 2 dict dup begin /lenIV -1 def end def
        /CharStrings 2 dict dup begin
          /.notdef <8BF8EC0D0E> def
          /A <8BF8EC0D8B8B15F8888B8BF950FC888B8BFDB005090E> def
        end def
        /Metrics 1 dict dup begin /A [10 700] def end def
      end definefont pop
      /F findfont 100 scalefont setfont (A) stringwidth
      """)
    let values = try await context.results()
    #expect(abs(try values[1].value(as: RealValue.self).value - 70) < 1e-9)
    #expect(abs(try values[0].value(as: RealValue.self).value) < 1e-9)
  }

  @Test func glyphTransformCacheKeyIgnoresIntegerTranslationButKeepsPhase() {
    let base = GraphicsMatrix(a: 2, b: 0, c: 0, d: 3, tx: 10.25, ty: -4.75)
    let translated = GraphicsMatrix(a: 2, b: 0, c: 0, d: 3, tx: 101.25, ty: 27.25)
    let differentPhase = GraphicsMatrix(a: 2, b: 0, c: 0, d: 3, tx: 10.5, ty: -4.75)
    #expect(FontGlyphTransformKey(base) == FontGlyphTransformKey(translated))
    #expect(FontGlyphTransformKey(base) != FontGlyphTransformKey(differentPhase))
  }

  @Test func makefontTransformsNestedCompositeFontsButNotBaseFonts() async throws {
    let context = try await Interpreter.execute(content: """
      /B /B 12 dict dup begin
        /FontType 3 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 1 1] def /Encoding StandardEncoding def
        /BuildGlyph { pop pop 0 0 setcharwidth } bind def
      end definefont def
      /C /C 12 dict dup begin
        /FontType 0 def /FontMatrix [2 0 0 2 0 0] def /FontBBox [0 0 0 0] def
        /FMapType 2 def /Encoding [0] def /FDepVector [B] def
      end definefont def
      /R /R 12 dict dup begin
        /FontType 0 def /FontMatrix [3 0 0 3 0 0] def /FontBBox [0 0 0 0] def
        /FMapType 2 def /Encoding [0] def /FDepVector [C] def
      end definefont def
      R [4 0 0 4 0 0] makefont dup /FontMatrix get 0 get
      exch /FDepVector get 0 get dup /FontMatrix get 0 get
      exch /FDepVector get 0 get /FontMatrix get 0 get
      """)
    let values = try await context.results()
    #expect(try values[2].value(as: RealValue.self).value == 12)
    #expect(try values[1].value(as: RealValue.self).value == 24)
    #expect(abs(try values[0].value(as: RealValue.self).value - 0.001) < 1e-12)
  }

  @Test func charpathIncludesType3PaintedPaths() async throws {
    let context = try await Interpreter.execute(content: Self.type3Font + """
      /F findfont 100 scalefont setfont 0 0 moveto (A) false charpath pathbbox
      """)
    let values = try await context.results()
    #expect(abs(try values[3].value(as: RealValue.self).value) < 1e-9)
    #expect(abs(try values[2].value(as: RealValue.self).value) < 1e-9)
    #expect(abs(try values[1].value(as: RealValue.self).value - 60) < 1e-9)
    #expect(abs(try values[0].value(as: RealValue.self).value - 70) < 1e-9)
  }

  @Test func embeddedType42UsesACapableProviderAndAdvertisesItsTypes() async throws {
    let environment = InterpreterEnvironment(fontProviders: [EmbeddedSFNTProvider()])
    let context = try await Interpreter.execute(content: """
      42 /FontType resourcestatus { pop pop true } { false } ifelse
      11 /FontType resourcestatus { pop pop true } { false } ifelse
      2 /CIDFontType resourcestatus { pop pop true } { false } ifelse
      /T 12 dict dup begin
        /FontType 42 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 500 700] def /Encoding StandardEncoding def
        /CharStrings 2 dict dup begin /.notdef 0 def /A 1 def end def
        /sfnts [<000100000000000000000000>] def
      end definefont pop
      /T findfont 100 scalefont setfont (A) stringwidth
      """, environment: environment)
    let values = try await context.results()
    #expect(try values[4].value(as: BooleanValue.self).value)
    #expect(try values[3].value(as: BooleanValue.self).value)
    #expect(try values[2].value(as: BooleanValue.self).value)
    #expect(abs(try values[1].value(as: RealValue.self).value - 50) < 1e-9)
    #expect(abs(try values[0].value(as: RealValue.self).value) < 1e-9)
  }

  @Test func sfntFontTypesAreUnavailableWithoutACapableProvider() async throws {
    let context = try await Interpreter.execute(content: """
      42 /FontType resourcestatus 11 /FontType resourcestatus
      2 /CIDFontType resourcestatus
      """)
    let values = try await context.results()
    #expect(values.count == 3)
    #expect(values.allSatisfy { (try? $0.value(as: BooleanValue.self).value) == false })
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

private struct EmbeddedSFNTProvider: FontResourceProvider {
  let identifier = "test.embedded-sfnt"
  let supportedAssetFormats: Set<FontAsset.Format> = [.sfnt]

  func availableFontNames() async throws -> [String] { [] }

  func resolve(_ query: FontResourceQuery) async throws -> FontProviderFace? { nil }

  func open(_ asset: FontAsset) async throws -> FontProviderFace? {
    FontProviderFace(providerIdentifier: identifier, faceKey: "face-\(asset.faceIndex)", asset: asset)
  }

  func glyph(_ selector: FontGlyphSelector, in face: FontProviderFace) async throws -> FontGlyph? {
    FontGlyph(
      selector: selector,
      metrics: FontGlyphMetrics(horizontalAdvance: FontPoint(x: 500, y: 0)),
      program: .outline(FontOutline(elements: [
        .move(FontPoint(x: 0, y: 0)),
        .line(FontPoint(x: 500, y: 0)),
        .line(FontPoint(x: 250, y: 700)),
        .close,
      ]))
    )
  }
}
