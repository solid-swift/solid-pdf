import Foundation
import SolidPostScript
import SolidPostScriptPlutoVG
import SolidPostScriptRaster
import SolidRaster
import Testing

@Suite struct RasterImageTargetTests {
  @Test func rendererWithoutTransmittedPageProducesNoSurface() throws {
    let renderer = try RasterImageTarget(pixelWidth: 20, pixelHeight: 20).makeRenderer()

    #expect(try renderer.finish().isEmpty)
  }

  @Test func defaultRenderProducesLetterRasterPage() async throws {
    let result = try await Interpreter.render(content: "0 0 20 20 rectfill showpage")
    let image = try #require(result.output.first)
    #expect(image.width == 612)
    #expect(image.height == 792)
    #expect(image.pixelFormat == .rgba8Unorm)
    #expect(try gray(x: 10, y: 782, image: image) < 0.1)
  }

  @Test func fillsClipsCurvesAndEvenOddPaths() async throws {
    let program = """
    0 0 moveto 25 0 lineto 25 50 lineto 0 50 lineto closepath clip
    0 15 moveto 50 15 lineto 50 35 lineto 0 35 lineto closepath eoclip
    10 0 translate
    -10 5 moveto 35 5 35 45 35 45 curveto -10 45 lineto closepath fill
    showpage
    """
    let result = try await Interpreter.render(
      content: program,
      to: RasterImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let image = try #require(result.output.first)
    #expect(try gray(x: 12, y: 25, image: image) < 0.1)
    #expect(try gray(x: 12, y: 5, image: image) > 0.9)
    #expect(try gray(x: 40, y: 25, image: image) > 0.9)
  }

  @Test func strokeDashColorImageAndPageLifecycleRender() async throws {
    let program = """
    0 0 1 setrgbcolor 0 10 20 10 rectfill
    20 10 scale
    2 1 8 [2 0 0 1 0 0] <ff000000ff00> false 3 colorimage
    copypage showpage
    """
    let result = try await Interpreter.render(
      content: program,
      to: RasterImageTarget(pixelWidth: 20, pixelHeight: 20)
    )
    #expect(result.output.count == 2)
    let painted = try #require(result.output.first)
    let cleared = try #require(result.output.last)
    #expect(try rgb(x: 5, y: 15, image: painted).red > 0.9)
    #expect(try rgb(x: 15, y: 15, image: painted).green > 0.9)
    #expect(try rgb(x: 10, y: 5, image: painted).blue > 0.9)
    #expect(try gray(x: 10, y: 10, image: cleared) > 0.9)
  }

  @Test func singularStrokeMatrixProducesNoMark() async throws {
    let result = try await Interpreter.render(
      content: "0 0 moveto 40 40 lineto [1 0 0 0 0 0] setmatrix stroke showpage",
      to: RasterImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    #expect(try gray(x: 20, y: 30, image: #require(result.output.first)) > 0.9)
  }

  @Test func nativeAndPlutoAgreeAwayFromAntialiasedEdges() async throws {
    let program = "0.25 setgray 5 5 moveto 35 5 lineto 35 35 lineto 5 35 lineto closepath fill showpage"
    let native = try await Interpreter.render(
      content: program,
      to: RasterImageTarget(pixelWidth: 40, pixelHeight: 40)
    )
    let pluto = try await Interpreter.render(
      content: program,
      to: PlutoVGImageTarget(pixelWidth: 40, pixelHeight: 40)
    )
    let nativeGray = try gray(x: 20, y: 20, image: #require(native.output.first))
    let plutoGray = try gray(x: 20, y: 20, image: #require(pluto.output.first))
    #expect(abs(nativeGray - plutoGray) < 0.02)
  }

  @Test func concurrentRendersSharingEnvironmentRemainIndependent() async throws {
    let environment = InterpreterEnvironment()
    async let black = Interpreter.render(
      content: "0 0 20 20 rectfill showpage",
      to: RasterImageTarget(pixelWidth: 20, pixelHeight: 20),
      environment: environment
    )
    async let gray = Interpreter.render(
      content: "0.5 setgray 0 0 20 20 rectfill showpage",
      to: RasterImageTarget(pixelWidth: 20, pixelHeight: 20),
      environment: environment
    )
    let (blackResult, grayResult) = try await (black, gray)
    #expect(try self.gray(x: 10, y: 10, image: #require(blackResult.output.first)) < 0.1)
    let grayValue = try self.gray(x: 10, y: 10, image: #require(grayResult.output.first))
    #expect(abs(grayValue - 0.5) < 0.03)
  }

  @Test func invalidConfigurationAndGeometryUsePostScriptErrors() throws {
    #expect(throws: SolidPostScript.Error.configurationError) {
      _ = try RasterImageTarget(pixelWidth: 0, pixelHeight: 10).makeRenderer()
    }
    let target = RasterImageTarget(pixelWidth: 10, pixelHeight: 10)
    let renderer = try target.makeRenderer()
    let path = GraphicsPath(elements: [
      .move(to: GraphicsPoint(x: Double.greatestFiniteMagnitude, y: 0)),
      .line(to: GraphicsPoint(x: 1, y: 1)),
    ])
    let state = GraphicsStateSnapshot(
      matrix: .identity,
      path: path,
      clip: GraphicsClip(imageableBounds: target.deviceDescriptor.imageableBounds),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )
    #expect(throws: SolidPostScript.Error.ioError) {
      try renderer.process(GraphicsEvent(operation: .paint(.fill(.winding)), before: state, after: state))
    }
  }

  private func gray(x: Int, y: Int, image: RasterImage) throws -> Double {
    let offset = y * image.bytesPerRow + x * 4
    guard x >= 0, y >= 0, x < image.width, y < image.height, offset + 3 < image.data.count else {
      throw SolidPostScript.Error.rangeCheck
    }
    return Double(image.data[offset]) / 255
  }

  private func rgb(
    x: Int,
    y: Int,
    image: RasterImage
  ) throws -> (red: Double, green: Double, blue: Double) {
    let offset = y * image.bytesPerRow + x * 4
    guard x >= 0, y >= 0, x < image.width, y < image.height, offset + 3 < image.data.count else {
      throw SolidPostScript.Error.rangeCheck
    }
    return (
      Double(image.data[offset]) / 255,
      Double(image.data[offset + 1]) / 255,
      Double(image.data[offset + 2]) / 255
    )
  }
}
