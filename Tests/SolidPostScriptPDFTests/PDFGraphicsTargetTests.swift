import Foundation
import SolidPDF
import SolidPostScript
import SolidPostScriptPDF
import Testing

@Suite
struct PDFGraphicsTargetTests {
  @Test(arguments: PDFVersion.allCases)
  func rendersVectorPageInEachVersion(_ version: PDFVersion) async throws {
    let target = PDFDataGraphicsTarget(
      sink: PDFDataOutputSink(),
      options: PDFRenderOptions(version: version, compressionLevel: 0)
    )
    let result = try await Interpreter.render(
      content: "1 0 0 setrgbcolor 10 20 30 40 rectfill showpage",
      to: target
    )
    #expect(result.output.version == version)
    #expect(result.output.pageCount == 1)
    #expect(result.output.data.containsASCII("/Type /Catalog"))
    #expect(result.output.data.containsASCII("/Type /Page"))
    #expect(result.output.diagnostics.isEmpty)
  }

  @Test
  func preservesDynamicPageSizesAndCopies() async throws {
    let result = try await Interpreter.render(
      content: "<< /PageSize [120 80] /NumCopies 2 >> setpagedevice showpage",
      to: PDFDataGraphicsTarget(sink: PDFDataOutputSink())
    )
    #expect(result.output.pageCount == 2)
    #expect(result.output.data.containsASCII("/MediaBox [0 0 120 80]"))
    #expect(result.output.data.containsASCII("/Count 2"))
  }

  @Test
  func reportsAssignedPageReferences() throws {
    let renderer = PDFDataGraphicsTarget(sink: PDFDataOutputSink()).makeRenderer()
    let state = GraphicsStateSnapshot.fixture(font: .invalid)
    try renderer.transmitPage(.init(operation: .page(.show), before: state, after: state), copies: 2)
    _ = try renderer.finish()

    #expect(renderer.pages.map(\.pageReference?.objectNumber) == [4, 5])
  }

  @Test
  func emitsNativeImagesFormsShadingsAndOverprintState() async throws {
    let content = """
    true setoverprint
    /F << /FormType 1 /BBox [0 0 10 10] /Matrix matrix
      /PaintProc { pop 0 setgray 0 0 10 10 rectfill } >> def
    F execform
    /DeviceRGB setcolorspace
    << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 20 0]
      /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>
      /Extend [true true] >> shfill
    2 1 8 [2 0 0 1 0 0] <ff000000ff00> false 3 colorimage
    showpage
    """
    let result = try await Interpreter.render(
      content: content,
      to: PDFDataGraphicsTarget(sink: PDFDataOutputSink())
    )
    let data = result.output.data
    #expect(data.containsASCII("/Subtype /Image"))
    #expect(data.containsASCII("/Subtype /Form"))
    #expect(data.containsASCII("/ShadingType 4"))
    #expect(data.containsASCII("/OP true"))
  }

  @Test
  func emitsTilingPatternsAsNativePDFPatterns() async throws {
    let result = try await Interpreter.render(
      content: """
      /P << /PatternType 1 /PaintType 1 /TilingType 1
        /BBox [0 0 5 5] /XStep 5 /YStep 5
        /PaintProc { pop 0 setgray 0 0 2 2 rectfill }
      >> matrix makepattern def
      [/Pattern] setcolorspace P setcolor 0 0 20 20 rectfill showpage
      """,
      to: PDFDataGraphicsTarget(sink: PDFDataOutputSink())
    )
    #expect(result.output.data.containsASCII("/PatternType 1"))
    #expect(result.output.diagnostics.isEmpty)
  }

  @Test
  func nonNativeRenderingStateFallsBackOnceFromCapturedEffects() async throws {
    let result = try await Interpreter.render(
      content: "{ 1 exch sub } settransfer .25 setgray 0 0 20 20 rectfill showpage",
      to: PDFDataGraphicsTarget(
        sink: PDFDataOutputSink(),
        options: PDFRenderOptions(fallbackDPI: 144)
      )
    )
    #expect(result.output.pageCount == 1)
    #expect(result.output.data.containsASCII("/Subtype /Image"))
    #expect(result.output.diagnostics.contains { $0.message.contains("144.0 dpi") })
  }

  @Test
  func vectorOnlyModeRejectsRequiredRasterFallback() async {
    await #expect(throws: SolidPostScript.Error.ioError) {
      try await Interpreter.render(
        content: "{ 1 exch sub } settransfer .25 setgray 0 0 20 20 rectfill showpage",
        to: PDFDataGraphicsTarget(
          sink: PDFDataOutputSink(),
          options: PDFRenderOptions(fallbackPolicy: .vectorOnly)
        )
      )
    }
  }

  @Test
  func concurrentRenderersRemainIsolated() async throws {
    async let first = Interpreter.render(
      content: "0 setgray 0 0 10 10 rectfill showpage",
      to: PDFDataGraphicsTarget(sink: PDFDataOutputSink())
    )
    async let second = Interpreter.render(
      content: "1 setgray 0 0 20 20 rectfill showpage",
      to: PDFDataGraphicsTarget(sink: PDFDataOutputSink())
    )
    let outputs = try await [first.output, second.output]
    #expect(outputs.allSatisfy { $0.pageCount == 1 })
    #expect(outputs[0].data != outputs[1].data)
  }

  @Test
  func preservesPortableOutlineGlyphsAsPDFText() throws {
    let target = PDFDataGraphicsTarget(
      sink: PDFDataOutputSink(),
      options: .init(compressionLevel: 0)
    )
    let renderer = target.makeRenderer()
    let font = GraphicsFontDescription(
      identifier: .init("fixture"),
      postScriptName: "Fixture"
    )
    let path = GraphicsPath(elements: [
      .move(to: .init(x: 0, y: 0)),
      .line(to: .init(x: 500, y: 0)),
      .line(to: .init(x: 250, y: 700)),
      .close,
    ])
    let glyph = GraphicsGlyphDescription(
      selector: .name("A"),
      metrics: .init(
        horizontalAdvance: .init(x: 600, y: 0),
        bounds: .init(x: 0, y: 0, width: 500, height: 700)
      ),
      program: .outline(path)
    )
    let run = GraphicsGlyphRun(rootFont: font, glyphs: [
      .init(
        glyph: glyph,
        origin: .init(x: 20, y: 30),
        transform: .init(a: 0.1, b: 0, c: 0, d: 0.1, tx: 20, ty: 30),
        advance: .init(x: 60, y: 0)
      ),
    ])
    let state = GraphicsStateSnapshot.fixture(font: font)
    try renderer.process(.init(operation: .paint(.text(run)), before: state, after: state))
    try renderer.transmitPage(.init(operation: .page(.show), before: state, after: state), copies: 1)
    let output = try renderer.finish()
    #expect(output.data.containsASCII("/Subtype /Type3"))
    #expect(output.data.containsASCII("BT"))
    #expect(output.data.containsASCII("<00> Tj"))
  }
}

private extension GraphicsStateSnapshot {
  static func fixture(font: GraphicsFontDescription) -> Self {
    Self(
      matrix: .identity,
      path: .init(),
      clip: .init(imageableBounds: .init(x: 0, y: 0, width: 612, height: 792)),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: .init(),
      font: font
    )
  }
}

private extension Data {
  func containsASCII(_ string: String) -> Bool {
    range(of: Data(string.utf8)) != nil
  }
}
