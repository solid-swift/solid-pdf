import Foundation
import SolidFont
import SolidPDF
import SolidPDFGraphics
import SolidPostScript
#if canImport(CoreGraphics)
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
  func rejectsTextPaintingAndReturnsNoResult() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(content: "BT (text) Tj ET")))
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
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

  @Test
  func decodesCompositeCodesAndPrefersToUnicodeMetadata() async throws {
    let toUnicode = streamObject(
      dictionary: "",
      data: Data("""
        1 begincodespacerange <0000> <ffff> endcodespacerange
        1 beginbfchar <002a> <D83DDE00> endbfchar
        """.utf8)
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
  func rejectsMalformedICCProfileBeforePainting() async throws {
    let profile = streamObject(dictionary: "/N 3 /Alternate /DeviceRGB", data: Data(repeating: 0, count: 128))
    let resources = "<< /ColorSpace << /ICC [/ICCBased 5 0 R] >> >>"
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/ICC cs 0 0 0 sc 0 0 1 1 re f",
      resources: resources,
      extraObjects: [profile]
    )))
    await #expect(throws: PDFGraphicsError.self) {
      try await document.render(page: 0, to: RecordingGraphicsTarget())
    }
    await document.close()
  }

  private func fixture(
    content: String,
    resources: String = "<< >>",
    extraObjects: [Data] = []
  ) -> Data {
    var objects = [
      Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
      Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
      Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources \(resources) /Contents 4 0 R >>".utf8),
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
