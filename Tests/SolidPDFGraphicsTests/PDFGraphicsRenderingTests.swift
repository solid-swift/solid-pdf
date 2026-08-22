import Foundation
import SolidFont
import SolidPDF
import SolidPDFGraphics
import SolidPostScript
#if canImport(CoreGraphics)
  import CoreGraphics
  import SolidPostScriptCoreGraphics
#endif
import SolidPostScriptPDF
import SolidPostScriptPlutoVG
import SolidPostScriptRaster
import Testing

@Suite
struct PDFGraphicsRenderingTests {
  @Test
  func rendersCallerOrderedRepeatedPagesThroughRecordingTarget() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "1 0 0 rg 10 20 30 40 re f"
    )))

    let result = try await document.render(
      selection: .indices([0, 0]),
      to: RecordingGraphicsTarget()
    )

    #expect(result.pages.map(\.pageIndex) == [0, 0])
    #expect(result.output.pages.count == 2)
    #expect(result.output.pages.allSatisfy { page in
      page.effects.contains { effect in
        if case .fill = effect { true } else { false }
      }
    })
    #expect(result.pages[0].device.descriptor.mediaBounds.width == 100)
    await document.close()
  }

  @Test
  func preservesMarkedContentPropertiesAndReplacementText() async throws {
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
        /FirstChar 65 /LastChar 65 /Widths [600] /Encoding /WinAnsiEncoding >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Span << /MCID 7 /Lang (en-US) /ActualText (Logical) >> BDC BT /F1 12 Tf (A) Tj ET EMC",
      resources: resources
    )))
    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: .init(providers: [SyntheticPDFFontProvider()])
    )
    let effects = result.output.pages[0].effects
    guard case .markedContent(.begin(let scope), _)? = effects.first else {
      Issue.record("Expected a marked-content boundary")
      return
    }
    #expect(scope.properties.identifier?.value == 7)
    #expect(scope.properties.language == "en-US")
    let run = try #require(effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)
    #expect(run.textReplacement?.text == "Logical")
    #expect(run.textReplacement?.provenance == .markedContent)
    await document.close()
  }

  @Test
  func extractsPhysicalAndStructureOrderedTextWithStructureActualText() async throws {
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
        /FirstChar 65 /LastChar 66 /Widths [600 600] /Encoding /WinAnsiEncoding >> >> >>
      """
    let content = """
      /P << /MCID 1 >> BDC BT /F1 12 Tf (B) Tj ET EMC
      /P << /MCID 0 >> BDC BT /F1 12 Tf (A) Tj ET EMC
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: content,
      resources: resources,
      catalogExtras: "/StructTreeRoot 5 0 R",
      pageExtras: "/StructParents 0",
      extraObjects: [
        Data("<< /Type /StructTreeRoot /K [6 0 R] >>".utf8),
        Data("<< /Type /StructElem /S /Document /P 5 0 R /K [7 0 R 8 0 R] >>".utf8),
        Data("<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /ActualText (First logical) /K 0 >>".utf8),
        Data("<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K 1 >>".utf8),
      ]
    )))
    let fontEnvironment = PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    let structured = try await document.extractedText(options: .init(fontEnvironment: fontEnvironment))
    #expect(try await structured.next()?.spans.map(\.text) == ["First logical", "B"])
    await structured.close()
    let physical = try await document.extractedText(options: .init(
      order: .physical,
      fontEnvironment: fontEnvironment
    ))
    #expect(try await physical.next()?.spans.map(\.text) == ["B", "A"])
    await physical.close()
    await document.close()
  }

  @Test
  func evaluatesOptionalContentAndPreservesHiddenScope() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/OC /Layer BDC 0 0 20 20 re f EMC",
      resources: "<< /Properties << /Layer 5 0 R >> >>",
      catalogExtras: "/OCProperties << /OCGs [5 0 R] /D << /BaseState /OFF >> >>",
      extraObjects: [Data("<< /Type /OCG /Name (Layer) >>".utf8)]
    )))
    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .markedContent(.begin(let scope), _)? = result.output.pages[0].effects.first else {
      Issue.record("Expected an optional-content boundary")
      return
    }
    #expect(!scope.visibility.isVisible)
    let hiddenRaster = try await document.render(
      page: 0, to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    let blankDocument = try await PDFDocument(source: PDFDataInputSource(fixture(content: "")))
    let blankRaster = try await blankDocument.render(
      page: 0, to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    #expect(hiddenRaster.output[0].data == blankRaster.output[0].data)
    await blankDocument.close()
    await document.close()
  }

  @Test
  func streamsImageRowsAndRetainsSourceSamples() async throws {
    let image = "<< /Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 6 >>\nstream\n\u{00}\u{00}\u{00}\u{ff}\u{00}\u{00}\nendstream"
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Im Do",
      resources: "<< /XObject << /Im 5 0 R >> >>",
      extraObjects: [image.data(using: .isoLatin1)!]
    )))

    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let captured, _)? = result.output.pages.first?.effects.first else {
      Issue.record("Expected a recorded image")
      await document.close()
      return
    }
    #expect(captured.descriptor.width == 2)
    #expect(captured.components == [0, 0, 0, 1, 0, 0])
    #expect(captured.rawSamples?.count == 12)
    await document.close()
  }

  @Test
  func rendersBlendModesAndConstantAlphaThroughNativeRaster() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        fixture(
          content: "0 0 1 rg 0 0 100 100 re f /Blend gs 1 0 0 rg 0 0 100 100 re f",
          resources: "<< /ExtGState << /Blend << /BM /Multiply /ca 0.5 >> >> >>"
        )
      )
    )
    let recording = try await document.render(page: 0, to: RecordingGraphicsTarget())
    let fills = recording.output.pages[0].effects
      .compactMap { effect -> GraphicsStateSnapshot? in
        if case .fill(_, _, let state) = effect { return state }
        return nil
      }
    #expect(fills.last?.transparency.blendMode == .multiply)
    #expect(fills.last?.transparency.constantAlpha == 0.5)

    let raster = try await document.render(
      page: 0,
      to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    let image = try #require(raster.output.first)
    let offset = 50 * image.bytesPerRow + 50 * 4
    #expect(image.data[offset] < 8)
    #expect(image.data[offset + 1] < 8)
    #expect(abs(Int(image.data[offset + 2]) - 128) < 8)

    let pluto = try await document.render(
      page: 0,
      to: PlutoVGImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    let plutoImage = try #require(pluto.output.first)
    #expect(abs(Int(plutoImage.data[offset]) - Int(image.data[offset])) < 8)
    #expect(abs(Int(plutoImage.data[offset + 1]) - Int(image.data[offset + 1])) < 8)
    #expect(abs(Int(plutoImage.data[offset + 2]) - Int(image.data[offset + 2])) < 8)
    #if canImport(CoreGraphics)
      let coreGraphics = try await document.render(
        page: 0,
        to: CoreGraphicsImageTarget(pixelWidth: 100, pixelHeight: 100)
      )
      let coreGraphicsPixel = try coreGraphicsRGB(atX: 50, y: 50, in: #require(coreGraphics.output.first))
      #expect(abs(coreGraphicsPixel.red - Double(image.data[offset]) / 255) < 0.04)
      #expect(abs(coreGraphicsPixel.green - Double(image.data[offset + 1]) / 255) < 0.04)
      #expect(abs(coreGraphicsPixel.blue - Double(image.data[offset + 2]) / 255) < 0.04)
    #endif
    await document.close()
  }

  @Test
  func rendersLuminositySoftMasksThroughNativeRaster() async throws {
    let maskContent = "0.5 g 0 0 100 100 re f"
    let maskGroup = """
      << /Type /XObject /Subtype /Form /BBox [0 0 100 100]
         /Group << /S /Transparency /I true /CS /DeviceGray >>
         /Resources << >> /Length \(maskContent.utf8.count) >>
      stream
      \(maskContent)
      endstream
      """
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        fixture(
          content: "0 0 1 rg 0 0 100 100 re f /Mask gs 1 0 0 rg 0 0 100 100 re f",
          resources: "<< /ExtGState << /Mask << /SMask << /S /Luminosity /G 5 0 R >> >> >> >>",
          extraObjects: [Data(maskGroup.utf8)]
        )
      )
    )
    let raster = try await document.render(
      page: 0,
      to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    let image = try #require(raster.output.first)
    let offset = 50 * image.bytesPerRow + 50 * 4
    #expect(abs(Int(image.data[offset]) - 128) < 8)
    #expect(image.data[offset + 1] < 8)
    #expect(abs(Int(image.data[offset + 2]) - 128) < 8)

    let pluto = try await document.render(
      page: 0,
      to: PlutoVGImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    let plutoImage = try #require(pluto.output.first)
    #expect(abs(Int(plutoImage.data[offset]) - Int(image.data[offset])) < 8)
    #expect(abs(Int(plutoImage.data[offset + 1]) - Int(image.data[offset + 1])) < 8)
    #expect(abs(Int(plutoImage.data[offset + 2]) - Int(image.data[offset + 2])) < 8)
    #if canImport(CoreGraphics)
      let coreGraphics = try await document.render(
        page: 0,
        to: CoreGraphicsImageTarget(pixelWidth: 100, pixelHeight: 100)
      )
      let coreGraphicsPixel = try coreGraphicsRGB(atX: 50, y: 50, in: #require(coreGraphics.output.first))
      #expect(abs(coreGraphicsPixel.red - Double(image.data[offset]) / 255) < 0.04)
      #expect(abs(coreGraphicsPixel.green - Double(image.data[offset + 1]) / 255) < 0.04)
      #expect(abs(coreGraphicsPixel.blue - Double(image.data[offset + 2]) / 255) < 0.04)
    #endif
    await document.close()
  }

  @Test
  func rejectsTextPaintingAndReturnsNoResult() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(content: "BT (text) Tj ET")))
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
    await document.close()
  }

  @Test
  func rendersPurposeEligibleAnnotationAppearancesAfterPageContent() async throws {
    let appearanceContent = "1 0 0 rg 0 0 10 10 re f"
    let appearance = streamObject(
      dictionary: "/Type /XObject /Subtype /Form /BBox [0 0 10 10] /Resources <<>>",
      data: Data(appearanceContent.utf8)
    )
    let annotation = Data(
      "<< /Type /Annot /Subtype /Square /P 3 0 R /Rect [20 30 60 70] /F 4 /AP << /N 6 0 R >> >>".utf8
    )
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "0 0 1 rg 0 0 100 100 re f",
      pageExtras: "/Annots [5 0 R]",
      extraObjects: [annotation, appearance]
    )))
    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    #expect(result.pages[0].renderedAnnotations.map(\.reference.objectNumber) == [5])
    #expect(result.output.pages[0].effects.contains { effect in
      if case .form = effect { true } else { false }
    })

    let extraction = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      options: .init(accessPurpose: .extraction)
    )
    #expect(extraction.pages[0].renderedAnnotations.isEmpty)
    await document.close()
  }

  @Test
  func enforcesStrictMissingAppearancesAndExplicitAnnotationSuppression() async throws {
    let annotation = Data(
      "<< /Type /Annot /Subtype /Text /P 3 0 R /Rect [1 2 10 12] /Contents (Note) >>".utf8
    )
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "",
      pageExtras: "/Annots [5 0 R]",
      extraObjects: [annotation]
    )))
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      options: .init(annotationRenderingPolicy: .none)
    )
    #expect(result.pages[0].renderedAnnotations.isEmpty)
    await document.close()
  }

  @Test
  func interpretsTextRunsUsingPDFWidthsSpacingAndSourceRanges() async throws {
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
        /FirstChar 65 /LastChar 66 /Widths [600 700] /Encoding /WinAnsiEncoding >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F1 10 Tf 2 Tc 1 0 0 1 10 20 Tm [(A) 120 (B)] TJ ET",
      resources: resources
    )))

    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    )
    let run = try #require(result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)

    #expect(run.sourceBytes == Data("AB".utf8))
    #expect(run.glyphs.map(\.sourceRange) == [0..<1, 1..<2])
    #expect(run.glyphs.map(\.unicodeScalars) == [["A".unicodeScalars.first!], ["B".unicodeScalars.first!]])
    #expect(run.glyphs.map(\.unicodeProvenance) == [.pdfEncoding, .pdfEncoding])
    #expect(run.glyphs[0].advance == GraphicsPoint(x: 8, y: 0))
    #expect(run.glyphs[1].advance == GraphicsPoint(x: 9, y: 0))
    #expect(abs(run.glyphs[1].origin.x - run.glyphs[0].origin.x - 6.8) < 0.000_001)
    await document.close()
  }

  @Test
  func rendersEmbeddedEncryptedType1WithoutAProvider() async throws {
    let descriptor = Data(
      "<< /Type /FontDescriptor /FontName /Fixture /FontBBox [0 0 500 700] /FontFile 6 0 R >>".utf8
    )
    let fontFile = streamObject(dictionary: "", data: pdfType1Fixture())
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Fixture
        /FirstChar 65 /LastChar 65 /Widths [600]
        /Encoding << /Differences [65 /A] >> /FontDescriptor 5 0 R >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F1 20 Tf (A) Tj ET",
      resources: resources,
      extraObjects: [descriptor, fontFile]
    )))

    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    let run = try #require(result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)
    #expect(run.rootFont.technology == .type1)
    #expect(run.glyphs[0].glyph.metrics.horizontalAdvance == GraphicsPoint(x: 600, y: 0))
    guard case .outline = run.glyphs[0].glyph.program else {
      Issue.record("Expected an owned Type 1 outline")
      await document.close()
      return
    }
    await document.close()
  }

  @Test
  func emitsInvisibleTextWithoutLosingExtractionMetadata() async throws {
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
        /FirstChar 65 /LastChar 65 /Widths [600] /Encoding /WinAnsiEncoding >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F1 12 Tf 3 Tr (A) Tj ET",
      resources: resources
    )))

    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    )
    let run = try #require(result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)
    #expect(run.renderingMode == .invisible)
    #expect(run.glyphs[0].unicodeScalars == ["A".unicodeScalars.first!])
    await document.close()
  }

  @Test(arguments: Array(0...7))
  func preservesEveryPDFTextRenderingMode(_ rawMode: Int) async throws {
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
        /FirstChar 65 /LastChar 65 /Widths [600] /Encoding /WinAnsiEncoding >> >> >>
      """
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        fixture(
          content: "BT /F1 12 Tf \(rawMode) Tr (A) Tj ET",
          resources: resources
        )
      )
    )
    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    )
    let run = try #require(
      result.output.pages[0].effects
        .compactMap { effect -> GraphicsGlyphRun? in
          if case .text(let run, _) = effect { return run }
          return nil
        }
        .first
    )
    #expect(run.renderingMode.rawValue == rawMode)
    #expect(run.style?.fill.colorSpace == .deviceGray)
    #expect(run.style?.stroke.colorSpace == .deviceGray)
    await document.close()
  }

  @Test
  func preservesIndependentTextFillAndStrokeAlpha() async throws {
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
        /FirstChar 65 /LastChar 65 /Widths [600] /Encoding /WinAnsiEncoding >> >>
         /ExtGState << /Alpha << /ca 0.25 /CA 0.75 /BM /Multiply >> >> >>
      """
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        fixture(
          content: "/Alpha gs BT /F1 12 Tf 2 Tr (A) Tj ET",
          resources: resources
        )
      )
    )
    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    )
    let run = try #require(
      result.output.pages[0].effects
        .compactMap { effect -> GraphicsGlyphRun? in
          if case .text(let run, _) = effect { return run }
          return nil
        }
        .first
    )
    #expect(run.style?.fillTransparency.constantAlpha == 0.25)
    #expect(run.style?.strokeTransparency.constantAlpha == 0.75)
    #expect(run.style?.fillTransparency.blendMode == .multiply)
    #expect(run.style?.strokeTransparency.blendMode == .multiply)
    await document.close()
  }

  @Test
  func decodesCompositeCodesAndPrefersToUnicodeMetadata() async throws {
    let toUnicode = streamObject(
      dictionary: "",
      data: Data(
        """
        1 begincodespacerange <0000> <ffff> endcodespacerange
        1 beginbfchar <002a> <D83DDE00> endbfchar
        """
        .utf8
      )
    )
    let resources = """
      << /Font << /F0 << /Type /Font /Subtype /Type0 /BaseFont /SyntheticCID
        /Encoding /Identity-H /ToUnicode 5 0 R
        /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /SyntheticCID
          /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>
          /DW 1000 /W [42 [500]] /CIDToGIDMap /Identity >>] >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F0 10 Tf <002a> Tj ET",
      resources: resources,
      extraObjects: [toUnicode]
    )))

    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    )
    let run = try #require(result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)
    #expect(run.sourceBytes == Data([0, 42]))
    #expect(run.glyphs[0].glyph.selector == .cid(42))
    #expect(run.glyphs[0].advance == GraphicsPoint(x: 5, y: 0))
    #expect(run.glyphs[0].unicodeScalars == ["😀".unicodeScalars.first!])
    #expect(run.glyphs[0].unicodeProvenance == .pdfToUnicode)
    await document.close()
  }

  @Test
  func executesAndCachesType3GlyphDisplayLists() async throws {
    let charProc = streamObject(
      dictionary: "",
      data: Data("500 0 0 0 500 700 d1 0 0 500 700 re f".utf8)
    )
    let resources = """
      << /Font << /F3 << /Type /Font /Subtype /Type3
        /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0]
        /CharProcs << /A 5 0 R >>
        /Encoding << /Type /Encoding /Differences [65 /A] >>
        /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F3 20 Tf 1 Tr (AA) Tj ET",
      resources: resources,
      extraObjects: [charProc]
    )))

    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    let run = try #require(result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)
    #expect(run.rootFont.technology == .type3)
    #expect(run.renderingMode == .stroke)
    #expect(run.glyphs.count == 2)
    #expect(run.glyphs[0].glyph.resourceIdentifier == run.glyphs[1].glyph.resourceIdentifier)
    guard case .displayList(let list) = run.glyphs[0].glyph.program else {
      Issue.record("Expected a captured Type 3 display list")
      await document.close()
      return
    }
    #expect(list.effects.contains { if case .fill = $0 { true } else { false } })
    #expect(run.glyphs[0].glyph.metrics.horizontalAdvance.x == 500)
    #expect(run.glyphs[0].glyph.metrics.bounds == GraphicsRect(x: 0, y: 0, width: 500, height: 700))
    await document.close()
  }

  @Test
  func suppressesInvisibleType3GlyphExecution() async throws {
    let charProc = streamObject(dictionary: "", data: Data("invalid-charproc-operator".utf8))
    let resources = """
      << /Font << /F3 << /Type /Font /Subtype /Type3
        /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0]
        /CharProcs << /A 5 0 R >>
        /Encoding << /Type /Encoding /Differences [65 /A] >>
        /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F3 20 Tf 3 Tr (A) Tj ET",
      resources: resources,
      extraObjects: [charProc]
    )))

    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    let run = try #require(result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)
    #expect(run.renderingMode == .invisible)
    #expect(run.glyphs[0].glyph.program == .empty)
    await document.close()
  }

  @Test
  func rejectsType3ArtworkBeforeMetrics() async throws {
    let charProc = streamObject(dictionary: "", data: Data("0 0 1 1 re f 500 0 d0".utf8))
    let resources = """
      << /Font << /F3 << /Type /Font /Subtype /Type3
        /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0]
        /CharProcs << /A 5 0 R >>
        /Encoding << /Type /Encoding /Differences [65 /A] >>
        /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F3 20 Tf (A) Tj ET",
      resources: resources,
      extraObjects: [charProc]
    )))
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
    await document.close()
  }

  @Test
  func implementsTextPositioningConvenienceOperatorsAndClipping() async throws {
    let resources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Synthetic
        /FirstChar 32 /LastChar 65 /Widths [250 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500
          500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 600]
        /Encoding /WinAnsiEncoding >> >> >>
      """
    let content = """
      BT /F1 10 Tf 12 TL 1 0 0 1 5 6 Tm (A) Tj
      10 20 Td (A) Tj 10 20 TD (A) Tj T* (A) Tj (A) ' 4 5 ( A) " ET
      BT /F1 10 Tf 4 Tr (A) Tj ET 0 0 10 10 re f
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(content: content, resources: resources)))
    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    )
    let runs = result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }
    #expect(runs.count == 7)
    #expect(runs[5].sourceBytes == Data(" A".utf8))
    #expect(runs[5].glyphs[0].advance.x == 11.5)
    #expect(runs[6].renderingMode == .fillClip)
    guard case .fill(_, _, let state) = result.output.pages[0].effects.last else {
      Issue.record("Expected fill after the text clipping operation")
      await document.close()
      return
    }
    #expect(!state.clip.constraints.isEmpty)
    await document.close()
  }

  @Test
  func appliesVerticalCIDMetricsWithoutBackendPositioning() async throws {
    let resources = """
      << /Font << /F0 << /Type /Font /Subtype /Type0 /BaseFont /SyntheticCID
        /Encoding /Identity-V
        /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /SyntheticCID
          /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>
          /DW 1000 /DW2 [880 -1000] /W2 [42 [-1200 400 900]] /CIDToGIDMap /Identity >>] >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F0 10 Tf <002a> Tj ET",
      resources: resources
    )))
    let result = try await document.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SyntheticPDFFontProvider()])
    )
    let run = try #require(result.output.pages[0].effects.compactMap { effect -> GraphicsGlyphRun? in
      if case .text(let run, _) = effect { return run }
      return nil
    }.first)
    #expect(run.rootFont.writingMode == 1)
    #expect(run.glyphs[0].glyph.selector == .cid(42))
    #expect(run.glyphs[0].glyph.metrics.verticalAdvance == GraphicsPoint(x: 0, y: -1_200))
    #expect(run.glyphs[0].glyph.metrics.verticalOrigin == GraphicsPoint(x: 400, y: 900))
    #expect(run.glyphs[0].advance == GraphicsPoint(x: 0, y: -12))
    await document.close()
  }

  @Test
  func reportsSimpleFontSubstitutionAndRejectsUnprovenCIDSubstitution() async throws {
    let simpleResources = """
      << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Unavailable
        /FirstChar 65 /LastChar 65 /Widths [600] /Encoding /WinAnsiEncoding >> >> >>
      """
    let simple = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F1 10 Tf (A) Tj ET",
      resources: simpleResources
    )))
    let simpleResult = try await simple.render(
      page: 0,
      to: RecordingGraphicsTarget(),
      fontEnvironment: PDFGraphicsFontEnvironment(providers: [SubstitutingPDFFontProvider(cidCompatible: false)])
    )
    #expect(simpleResult.diagnostics.map(\.identifier).contains("pdf.graphics.font-substitution"))
    await simple.close()

    let cidResources = """
      << /Font << /F0 << /Type /Font /Subtype /Type0 /BaseFont /UnavailableCID /Encoding /Identity-H
        /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /UnavailableCID
          /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>
          /CIDToGIDMap /Identity >>] >> >> >>
      """
    let cid = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F0 10 Tf <002a> Tj ET",
      resources: cidResources
    )))
    await #expect(throws: PDFGraphicsError.self) {
      try await cid.render(
        page: 0,
        to: RecordingGraphicsTarget(),
        fontEnvironment: PDFGraphicsFontEnvironment(providers: [SubstitutingPDFFontProvider(cidCompatible: false)])
      )
    }
    await cid.close()
  }

  @Test
  func rendersType3TextThroughBuiltInTargets() async throws {
    let charProc = streamObject(dictionary: "", data: Data("500 0 0 0 500 700 d1 0 0 500 700 re f".utf8))
    let resources = """
      << /Font << /F3 << /Type /Font /Subtype /Type3
        /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0]
        /CharProcs << /A 5 0 R >> /Encoding << /Differences [65 /A] >>
        /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BT /F3 40 Tf 1 0 0 1 20 20 Tm (A) Tj ET",
      resources: resources,
      extraObjects: [charProc]
    )))
    #expect(try await document.render(
      page: 0, to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    ).output.count == 1)
    #expect(try await document.render(
      page: 0, to: PlutoVGImageTarget(pixelWidth: 100, pixelHeight: 100)
    ).output.count == 1)
#if canImport(CoreGraphics)
    #expect(try await document.render(
      page: 0, to: CoreGraphicsImageTarget(pixelWidth: 100, pixelHeight: 100)
    ).output.count == 1)
#endif
    #expect(try await document.render(page: 0, to: RasterSeparationTarget()).output.count == 1)
    #expect(try await document.render(
      page: 0, to: PDFGraphicsTarget(sink: PDFDataOutputSink())
    ).output.pageCount == 1)
    await document.close()
  }

  @Test
  func parsesRawInlineImageWithoutScanningForEI() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BI /W 4 /H 1 /CS /G /BPC 8 ID A EI EI "
    )))
    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let image, _)? = result.output.pages.first?.effects.first else {
      Issue.record("Expected an inline image")
      await document.close()
      return
    }
    #expect(image.components == [0x41, 0x20, 0x45, 0x49].map { Float($0) / 255 })
    await document.close()
  }

  @Test
  func decodesFilteredInlineImageAtItsExactEndMarker() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BI /W 1 /H 1 /CS /G /BPC 8 /F [/AHx /RL] ID 004180> EI 0 0 1 1 re f"
    )))
    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let image, _)? = result.output.pages.first?.effects.first else {
      Issue.record("Expected a filtered inline image")
      await document.close()
      return
    }
    #expect(image.components == [Float(0x41) / 255])
    #expect(result.output.pages[0].effects.contains { if case .fill = $0 { true } else { false } })
    await document.close()
  }

  @Test
  func rejectsFilteredInlineImageWithoutEITerminator() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BI /W 1 /H 1 /CS /G /BPC 8 /F /AHx ID 41>"
    )))
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
    await document.close()
  }

  @Test
  func rawInlineImageResolvesNamedColorSpaceForItsExactLength() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "BI /W 1 /H 1 /CS /Mono /BPC 8 ID A EI ",
      resources: "<< /ColorSpace << /Mono /DeviceGray >> >>"
    )))
    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let image, _)? = result.output.pages.first?.effects.first else {
      Issue.record("Expected a named-color-space inline image")
      await document.close()
      return
    }
    #expect(image.components == [Float(0x41) / 255])
    await document.close()
  }

  @Test
  func streamsExplicitImageMaskRowsInThePrimaryImageTransaction() async throws {
    let image = streamObject(
      dictionary: "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Mask 6 0 R",
      data: Data([255, 0, 0, 0, 0, 255])
    )
    let mask = streamObject(
      dictionary: "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ImageMask true /Decode [0 1]",
      data: Data([0x40])
    )
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Im Do",
      resources: "<< /XObject << /Im 5 0 R >> >>",
      extraObjects: [image, mask]
    )))

    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let captured, _)? = result.output.pages.first?.effects.first else {
      Issue.record("Expected a masked image")
      await document.close()
      return
    }
    #expect(captured.descriptor.sourceType == .explicitMask)
    #expect(captured.mask?.opacities == [1, 0])
    await document.close()
  }

  @Test
  func reversesExplicitImageMaskDecode() async throws {
    let image = streamObject(
      dictionary: "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Mask 6 0 R",
      data: Data([255, 0, 0, 0, 0, 255])
    )
    let mask = streamObject(
      dictionary: "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ImageMask true /Decode [1 0]",
      data: Data([0x40])
    )
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Im Do",
      resources: "<< /XObject << /Im 5 0 R >> >>",
      extraObjects: [image, mask]
    )))

    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let captured, _)? = result.output.pages.first?.effects.first else {
      Issue.record("Expected a masked image")
      await document.close()
      return
    }
    #expect(captured.mask?.opacities == [0, 1])
    await document.close()
  }

  @Test
  func compilesFormAndAxialShadingResources() async throws {
    let formContent = "0 0 10 10 re f"
    let form = Data(
      "<< /Type /XObject /Subtype /Form /BBox [0 0 10 10] /Length \(formContent.utf8.count) >>\nstream\n\(formContent)\nendstream".utf8
    )
    let resources = """
      << /XObject << /Fm 5 0 R >>
         /Shading << /Sh << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0]
           /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >> >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Fm Do /Sh sh",
      resources: resources,
      extraObjects: [form]
    )))
    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    let effects = result.output.pages[0].effects
    #expect(effects.contains { if case .form = $0 { true } else { false } })
    #expect(effects.contains { if case .shading = $0 { true } else { false } })
    await document.close()
  }

  @Test(arguments: [6, 7])
  func compilesPatchMeshShadingsAndPreservesSourcePatches(type: Int) async throws {
    let sharedPointIndices = [1: [3, 4, 5, 6], 2: [6, 7, 8, 9], 3: [9, 10, 11, 0]]
    let sharedColorIndices = [1: [1, 2], 2: [2, 3], 3: [3, 0]]
    for flag in 1...3 {
      let shading = patchShading(type: type, continuationFlag: flag)
      let document = try await PDFDocument(source: PDFDataInputSource(fixture(
        content: "/Sh sh",
        resources: "<< /Shading << /Sh 5 0 R >> >>",
        extraObjects: [shading]
      )))

      let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
      guard case .shading(let captured, _)? = result.output.pages.first?.effects.first else {
        Issue.record("Expected a patch shading")
        await document.close()
        return
      }
      #expect(captured.type == type)
      #expect(captured.sourcePatches.count == 2)
      #expect(captured.sourcePatches[0].continuationFlag == 0)
      #expect(captured.sourcePatches[1].continuationFlag == flag)
      #expect(captured.sourcePatches[0].controlPoints.count == (type == 6 ? 12 : 16))
      let expectedPoints = sharedPointIndices[flag]!.map { captured.sourcePatches[0].controlPoints[$0] }
      #expect(Array(captured.sourcePatches[1].controlPoints.prefix(4)) == expectedPoints)
      let expectedColors = sharedColorIndices[flag]!.map { captured.sourcePatches[0].cornerComponents[$0] }
      #expect(Array(captured.sourcePatches[1].cornerComponents.prefix(2)) == expectedColors)
      #expect(!captured.mesh.triangles.isEmpty)
      if type == 7, flag == 1 { expectTensorCornerTopology(captured) }
      await document.close()
    }
  }

  @Test(arguments: [6, 7])
  func rejectsPatchContinuationWithoutPriorPatch(type: Int) async throws {
    let shading = patchShading(type: type, continuationFlag: 1, includeInitialPatch: false)
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Sh sh",
      resources: "<< /Shading << /Sh 5 0 R >> >>",
      extraObjects: [shading]
    )))
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
    await document.close()
  }

  @Test
  func reportsPortableICCAlternateAndPostScriptXObjectDiagnostics() async throws {
    let profile = streamObject(dictionary: "/N 3 /Alternate /DeviceRGB", data: iccProfile(componentSignature: "RGB "))
    let postScript = streamObject(dictionary: "/Type /XObject /Subtype /PS", data: Data())
    let resources = """
      << /ColorSpace << /ICC [/ICCBased 5 0 R] >>
         /XObject << /PS 6 0 R >> >>
      """
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/ICC cs 0 0 0 sc 0 0 1 1 re f /ICC cs 1 1 1 sc 1 1 1 1 re f /PS Do",
      resources: resources,
      extraObjects: [profile, postScript]
    )))

    let result = try await document.render(page: 0, to: RecordingGraphicsTarget())
    #expect(result.diagnostics.count { $0.identifier == "pdf.graphics.icc-alternate" } == 1)
    #expect(result.diagnostics.map(\.identifier).contains("pdf.graphics.postscript-xobject-ignored"))
    await document.close()
  }

  @Test
  func rendersImageMasksAndPatchMeshesThroughBuiltInTargets() async throws {
    let image = streamObject(
      dictionary: "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Mask 6 0 R",
      data: Data([255, 0, 0, 0, 0, 255])
    )
    let mask = streamObject(
      dictionary: "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ImageMask true",
      data: Data([0x40])
    )
    let shading = patchShading(type: 7, continuationFlag: 1)
    let resources = "<< /XObject << /Im 5 0 R >> /Shading << /Sh 7 0 R >> >>"
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Im Do /Sh sh",
      resources: resources,
      extraObjects: [image, mask, shading]
    )))

    let raster = try await document.render(
      page: 0,
      to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    #expect(raster.output.count == 1)
    let pluto = try await document.render(
      page: 0,
      to: PlutoVGImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    #expect(pluto.output.count == 1)
#if canImport(CoreGraphics)
    let coreGraphics = try await document.render(
      page: 0,
      to: CoreGraphicsImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    #expect(coreGraphics.output.count == 1)
#endif
    let separations = try await document.render(page: 0, to: RasterSeparationTarget())
    #expect(separations.output.count == 1)
    let bounds = GraphicsRect(x: 0, y: 0, width: 100, height: 100)
    let spool = try await document.render(
      page: 0,
      to: PrintSpoolGraphicsTarget(deviceDescriptor: GraphicsDeviceDescriptor(
        mediaBounds: bounds,
        imageableBounds: bounds,
        horizontalResolution: 72,
        verticalResolution: 72,
        defaultMatrix: .identity
      ))
    )
    #expect(spool.output.pages.count == 1)
    let pdf = try await document.render(
      page: 0,
      to: PDFGraphicsTarget(sink: PDFDataOutputSink())
    )
    #expect(pdf.output.pageCount == 1)
    await document.close()
  }

  @Test
  func rendersSampledImageSoftMasks() async throws {
    let image = streamObject(
      dictionary:
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask 6 0 R",
      data: Data([255, 0, 0])
    )
    let mask = streamObject(
      dictionary: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8",
      data: Data([128])
    )
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        fixture(
          content: "0 0 1 rg 0 0 100 100 re f 100 0 0 100 0 0 cm /Im Do",
          resources: "<< /XObject << /Im 5 0 R >> >>",
          extraObjects: [image, mask]
        )
      )
    )
    let recording = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let captured, _)? = recording.output.pages[0].effects.last else {
      Issue.record("Expected a sampled image effect")
      await document.close()
      return
    }
    #expect(captured.descriptor.sourceType == .softMask)
    #expect(captured.mask?.opacities == [Float(128) / 255])

    let raster = try await document.render(
      page: 0,
      to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    let rendered = try #require(raster.output.first)
    let offset = 50 * rendered.bytesPerRow + 50 * 4
    #expect(abs(Int(rendered.data[offset]) - 128) < 8)
    #expect(rendered.data[offset + 1] < 8)
    #expect(abs(Int(rendered.data[offset + 2]) - 127) < 8)
    await document.close()
  }

  @Test
  func unblendsSampledImageMatteBeforeColorConversion() async throws {
    let image = streamObject(
      dictionary:
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask 6 0 R",
      data: Data([255, 127, 127])
    )
    let mask = streamObject(
      dictionary:
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Matte [1 1 1]",
      data: Data([128])
    )
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        fixture(
          content: "0 0 1 rg 0 0 100 100 re f 100 0 0 100 0 0 cm /Im Do",
          resources: "<< /XObject << /Im 5 0 R >> >>",
          extraObjects: [image, mask]
        )
      )
    )
    let recording = try await document.render(page: 0, to: RecordingGraphicsTarget())
    guard case .image(let captured, _)? = recording.output.pages[0].effects.last else {
      Issue.record("Expected a sampled image effect")
      await document.close()
      return
    }
    #expect(abs(captured.components[0] - 1) < 0.000_001)
    #expect(abs(captured.components[1]) < 0.000_001)
    #expect(abs(captured.components[2]) < 0.000_001)
    #expect(captured.rawSamples == Data([0, 255, 0, 127, 0, 127]))

    let raster = try await document.render(
      page: 0,
      to: RasterImageTarget(pixelWidth: 100, pixelHeight: 100)
    )
    let rendered = try #require(raster.output.first)
    let offset = 50 * rendered.bytesPerRow + 50 * 4
    #expect(abs(Int(rendered.data[offset]) - 128) < 8)
    #expect(rendered.data[offset + 1] < 8)
    #expect(abs(Int(rendered.data[offset + 2]) - 127) < 8)
    await document.close()
  }

  @Test
  func rejectsMalformedICCProfileBeforePainting() async throws {
    let profile = streamObject(dictionary: "/N 3 /Alternate /DeviceRGB", data: Data(repeating: 0, count: 128))
    let resources = "<< /ColorSpace << /ICC [/ICCBased 5 0 R] >> >>"
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        fixture(
          content: "/ICC cs 0 0 0 sc 0 0 1 1 re f",
          resources: resources,
          extraObjects: [profile]
        )
      )
    )
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
    await document.close()
  }

  private func fixture(
    content: String,
    resources: String = "<< >>",
    catalogExtras: String = "",
    pageExtras: String = "",
    extraObjects: [Data] = []
  ) -> Data {
    var objects = [
      Data("<< /Type /Catalog /Pages 2 0 R \(catalogExtras) >>".utf8),
      Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
      Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources \(resources) /Contents 4 0 R \(pageExtras) >>".utf8),
      Data("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream".utf8),
    ]
    objects.append(contentsOf: extraObjects)
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

  private func streamObject(dictionary: String, data: Data) -> Data {
    var result = Data("<< \(dictionary) /Length \(data.count) >>\nstream\n".utf8)
    result.append(data)
    result.append(Data("\nendstream".utf8))
    return result
  }

  private func iccProfile(componentSignature: String) -> Data {
    var data = Data(repeating: 0, count: 128)
    data.replaceSubrange(0..<4, with: [0, 0, 0, 128])
    data.replaceSubrange(16..<20, with: componentSignature.utf8)
    data.replaceSubrange(36..<40, with: "acsp".utf8)
    return data
  }

  private func patchShading(
    type: Int,
    continuationFlag: Int?,
    includeInitialPatch: Bool = true
  ) -> Data {
    let boundary: [(UInt8, UInt8)] = [
      (0, 0), (0, 85), (0, 170), (0, 255),
      (85, 255), (170, 255), (255, 255),
      (255, 170), (255, 85), (255, 0),
      (170, 0), (85, 0),
    ]
    let interior: [(UInt8, UInt8)] = [(85, 85), (85, 170), (170, 170), (170, 85)]
    let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]]
    var data = Data()
    if includeInitialPatch {
      data.append(0)
      for point in boundary + (type == 7 ? interior : []) { data.append(contentsOf: [point.0, point.1]) }
      colors.forEach { data.append(contentsOf: $0) }
    }
    if let continuationFlag {
      data.append(UInt8(continuationFlag))
      let count = type == 6 ? 8 : 12
      for point in (boundary + interior).prefix(count) { data.append(contentsOf: [point.0, point.1]) }
      data.append(contentsOf: colors[2])
      data.append(contentsOf: colors[3])
    }
    return streamObject(
      dictionary: "/ShadingType \(type) /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1 0 1 0 1]",
      data: data
    )
  }

  private func expectTensorCornerTopology(_ shading: GraphicsShading) {
    let vertices = shading.mesh.triangles.flatMap { [$0.first, $0.second, $0.third] }
    let red = vertices.first { $0.paint == .deviceRGB(red: 1, green: 0, blue: 0) }
    let green = vertices.first { $0.paint == .deviceRGB(red: 0, green: 1, blue: 0) }
    let blue = vertices.first { $0.paint == .deviceRGB(red: 0, green: 0, blue: 1) }
    let white = vertices.first { $0.paint == .deviceRGB(red: 1, green: 1, blue: 1) }
    #expect(red != nil)
    #expect(green != nil)
    #expect(blue != nil)
    #expect(white != nil)
    if let red, let green, let blue, let white {
      #expect(red.position.x == green.position.x)
      #expect(green.position.y == blue.position.y)
      #expect(blue.position.x == white.position.x)
      #expect(white.position.y == red.position.y)
    }
  }

  private func pdfType1Fixture() -> Data {
    let notdef = pdfType1EncryptedCharString([139, 248, 136, 13, 14])
    let a = pdfType1EncryptedCharString([
      139, 248, 236, 13, 139, 139, 21,
      248, 136, 139, 5, 139, 249, 80, 5,
      252, 136, 139, 5, 139, 253, 80, 5, 9, 14,
    ])
    var privateProgram = Data([0, 0, 0, 0])
    privateProgram.append(Data("/lenIV 4 def /Subrs 0 array /CharStrings 2 dict dup begin ".utf8))
    privateProgram.append(Data("/.notdef \(notdef.count) RD ".utf8)); privateProgram.append(notdef)
    privateProgram.append(Data(" ND /A \(a.count) RD ".utf8)); privateProgram.append(a)
    privateProgram.append(Data(" ND end end".utf8))
    let encrypted = pdfType1Encrypt(privateProgram, seed: 55_665)
    let header = Data("%!PS-AdobeFont-1.0: Fixture 1.0\ncurrentfile eexec\n".utf8)
    var result = Data()
    appendPDFPFB(kind: 1, bytes: header, to: &result)
    appendPDFPFB(kind: 2, bytes: encrypted, to: &result)
    result.append(contentsOf: [0x80, 0x03])
    return result
  }

  private func pdfType1EncryptedCharString(_ bytes: [UInt8]) -> Data {
    pdfType1Encrypt(Data([0, 0, 0, 0] + bytes), seed: 4_330)
  }

  private func pdfType1Encrypt(_ plaintext: Data, seed: UInt16) -> Data {
    var state = seed
    var result = Data(capacity: plaintext.count)
    for byte in plaintext {
      let cipher = byte ^ UInt8(truncatingIfNeeded: state >> 8)
      result.append(cipher)
      state = UInt16(truncatingIfNeeded: (UInt32(cipher) + UInt32(state)) * 52_845 + 22_719)
    }
    return result
  }

  private func appendPDFPFB(kind: UInt8, bytes: Data, to result: inout Data) {
    result.append(contentsOf: [0x80, kind])
    let length = UInt32(bytes.count)
    result.append(UInt8(truncatingIfNeeded: length))
    result.append(UInt8(truncatingIfNeeded: length >> 8))
    result.append(UInt8(truncatingIfNeeded: length >> 16))
    result.append(UInt8(truncatingIfNeeded: length >> 24))
    result.append(bytes)
  }

  #if canImport(CoreGraphics)
    private func coreGraphicsRGB(
      atX x: Int,
      y: Int,
      in image: CGImage
    ) throws -> (red: Double, green: Double, blue: Double) {
      let provider = try #require(image.dataProvider)
      let data = try #require(provider.data)
      let bytes = try #require(CFDataGetBytePtr(data))
      let offset = y * image.bytesPerRow + x * 4
      return (
        Double(bytes[offset]) / 255,
        Double(bytes[offset + 1]) / 255,
        Double(bytes[offset + 2]) / 255
      )
    }
  #endif
}

private struct SyntheticPDFFontProvider: FontResourceProvider {
  let identifier = "tests.synthetic-pdf-font"

  func availableFontNames() async throws -> [String] { ["Synthetic"] }

  func resolve(_ query: FontResourceQuery) async throws -> FontProviderFace? {
    guard query.name == "Synthetic" || query.name == "SyntheticCID" else { return nil }
    let descriptor = try FontDescriptor(postScriptName: query.name, unitsPerEm: 1_000)
    let asset = try FontAsset(
      descriptor: descriptor,
      format: .type1,
      data: Data("%!PS-AdobeFont-1.0: Synthetic".utf8)
    )
    return FontProviderFace(
      providerIdentifier: identifier,
      faceKey: query.name,
      asset: asset
    )
  }

  func isCompatible(with systemInfo: FontCIDSystemInfo, face: FontProviderFace) async throws -> Bool {
    systemInfo.registry == "Adobe" && systemInfo.ordering == "Identity"
  }

  func glyph(_ selector: FontGlyphSelector, in face: FontProviderFace) async throws -> FontGlyph? {
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
      resolvedGlyphIndex: selector == .name("A") ? 1 : 2
    )
  }
}

private struct SubstitutingPDFFontProvider: FontResourceProvider {
  let identifier = "tests.substituting-pdf-font"
  let cidCompatible: Bool

  func availableFontNames() async throws -> [String] { ["Substitute"] }

  func resolve(_ query: FontResourceQuery) async throws -> FontProviderFace? {
    guard query.permitsSubstitution else { return nil }
    let descriptor = try FontDescriptor(postScriptName: "Substitute", unitsPerEm: 1_000)
    let asset = try FontAsset(descriptor: descriptor, format: .type1, data: Data("substitute".utf8))
    return FontProviderFace(
      providerIdentifier: identifier,
      faceKey: "substitute",
      asset: asset,
      isSubstitute: true
    )
  }

  func isCompatible(with systemInfo: FontCIDSystemInfo, face: FontProviderFace) async throws -> Bool {
    cidCompatible
  }

  func glyph(_ selector: FontGlyphSelector, in face: FontProviderFace) async throws -> FontGlyph? {
    try await SyntheticPDFFontProvider().glyph(selector, in: face)
  }
}
