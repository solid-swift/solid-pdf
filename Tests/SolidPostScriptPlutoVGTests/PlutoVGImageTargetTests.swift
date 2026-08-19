import Foundation
import Testing

import SolidPostScript
import SolidPostScriptPlutoVG

#if canImport(CoreGraphics)
import CoreGraphics
import SolidPostScriptCoreGraphics
#endif

@Suite
struct PlutoVGImageTargetTests {

  @Test func tilingPatternsRepeatTheirTransparentKeyCell() async throws {
    let result = try await Interpreter.render(
      content: """
      /p << /PatternType 1 /PaintType 1 /TilingType 1
        /BBox [0 0 10 10] /XStep 10 /YStep 10
        /PaintProc { pop 0 setgray 0 0 5 10 rectfill }
      >> matrix makepattern def
      /Pattern setcolorspace p setcolor 0 0 20 20 rectfill showpage
      """,
      to: PlutoVGImageTarget(pixelWidth: 20, pixelHeight: 20)
    )
    let image = try #require(result.output.first)
    #expect(try gray(atX: 2, y: 10, in: image) < 0.1)
    #expect(try gray(atX: 7, y: 10, in: image) > 0.9)
    #expect(try gray(atX: 12, y: 10, in: image) < 0.1)
  }

  @Test func axialShadingsRenderThroughThePortableFallbackMesh() async throws {
    let result = try await Interpreter.render(
      content: """
      << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 20 0]
         /Function << /FunctionType 2 /Domain [0 1]
                      /C0 [1 0 0] /C1 [0 0 1] /N 1 >>
         /Extend [true true] >> shfill showpage
      """,
      to: PlutoVGImageTarget(pixelWidth: 20, pixelHeight: 20)
    )
    let image = try #require(result.output.first)
    #expect(try red(atX: 2, y: 10, in: image) > 0.7)
    #expect(try blue(atX: 18, y: 10, in: image) > 0.7)
  }

  @Test func producesOwnedTopLeftRGBAImagesAndDiscardsTheFinalPage() async throws {
    let result = try await Interpreter.render(
      content: "0 0 moveto 30 0 lineto 30 10 lineto 0 10 lineto closepath fill showpage "
        + "showpage 0 0 moveto 30 30 lineto stroke",
      to: PlutoVGImageTarget(pixelWidth: 30, pixelHeight: 30)
    )

    #expect(result.output.count == 2)
    let first = try #require(result.output.first)
    let second = try #require(result.output.last)
    #expect(first.width == 30)
    #expect(first.height == 30)
    #expect(first.bytesPerRow == 120)
    #expect(first.pixelFormat == .rgba8Unorm)
    #expect(first.data.count == first.bytesPerRow * first.height)
    #expect(try gray(atX: 15, y: 25, in: first) < 0.1)
    #expect(try gray(atX: 15, y: 5, in: first) > 0.9)
    #expect(try gray(atX: 15, y: 25, in: second) > 0.9)
    #expect(try alpha(atX: 15, y: 25, in: first) == 1)
  }

  @Test func fillsCurvesAndOrderedClippingFromSnapshots() async throws {
    let program = """
    newpath 0 0 moveto 25 0 lineto 25 50 lineto 0 50 lineto closepath clip
    newpath 0 15 moveto 50 15 lineto 50 35 lineto 0 35 lineto closepath eoclip
    0 setgray
    10 0 translate
    newpath -10 5 moveto 35 5 35 45 35 45 curveto -10 45 lineto closepath fill
    showpage
    """
    let result = try await Interpreter.render(
      content: program,
      to: PlutoVGImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let image = try #require(result.output.first)

    #expect(try gray(atX: 12, y: 25, in: image) < 0.1)
    #expect(try gray(atX: 12, y: 5, in: image) > 0.9)
    #expect(try gray(atX: 40, y: 25, in: image) > 0.9)
  }

  @Test func evenOddFillPreservesTheInnerHole() async throws {
    let program = """
    2 2 moveto 38 2 lineto 38 38 lineto 2 38 lineto closepath
    12 12 moveto 28 12 lineto 28 28 lineto 12 28 lineto closepath eofill
    showpage
    """
    let result = try await Interpreter.render(
      content: program,
      to: PlutoVGImageTarget(pixelWidth: 40, pixelHeight: 40)
    )
    let image = try #require(result.output.first)

    #expect(try gray(atX: 6, y: 20, in: image) < 0.1)
    #expect(try gray(atX: 20, y: 20, in: image) > 0.9)
  }

  @Test func strokeStateDashAndErasePageAreApplied() async throws {
    let stroked = try await Interpreter.render(
      content: "0 setgray 6 setlinewidth 2 setlinecap [10 10] 0 setdash "
        + "5 25 moveto 45 25 lineto stroke showpage",
      to: PlutoVGImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let strokeImage = try #require(stroked.output.first)
    #expect(try gray(atX: 4, y: 25, in: strokeImage) < 0.1)
    #expect(try gray(atX: 20, y: 25, in: strokeImage) > 0.9)
    #expect(try gray(atX: 30, y: 25, in: strokeImage) < 0.1)

    let erased = try await Interpreter.render(
      content: "0 0 moveto 50 0 lineto 50 50 lineto 0 50 lineto closepath fill erasepage showpage",
      to: PlutoVGImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let erasedImage = try #require(erased.output.first)
    #expect(try gray(atX: 25, y: 25, in: erasedImage) > 0.9)
  }

  @Test func miterJoinUsesTheStrokeSnapshot() async throws {
    let result = try await Interpreter.render(
      content: "8 setlinewidth 0 setlinejoin 10 setmiterlimit "
        + "10 10 moveto 20 30 lineto 30 10 lineto stroke showpage",
      to: PlutoVGImageTarget(pixelWidth: 40, pixelHeight: 40)
    )
    let image = try #require(result.output.first)
    #expect(try gray(atX: 20, y: 4, in: image) < 0.1)
  }

  @Test func singularStrokeMatrixProducesNoVisibleMark() async throws {
    let result = try await Interpreter.render(
      content: "0 0 moveto 40 40 lineto [1 0 0 0 0 0] setmatrix stroke showpage",
      to: PlutoVGImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let image = try #require(result.output.first)
    #expect(try gray(atX: 20, y: 30, in: image) > 0.9)
  }

  @Test func imageableBoundsAndNonzeroMediaOriginAreRespected() async throws {
    let descriptor = GraphicsDeviceDescriptor(
      mediaBounds: GraphicsRect(x: 100, y: 200, width: 30, height: 20),
      imageableBounds: GraphicsRect(x: 105, y: 205, width: 20, height: 10),
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .identity
    )
    let program = "100 200 moveto 130 200 lineto 130 220 lineto 100 220 lineto closepath fill showpage"
    let result = try await Interpreter.render(
      content: program,
      to: PlutoVGImageTarget(pixelWidth: 30, pixelHeight: 20, deviceDescriptor: descriptor)
    )
    let image = try #require(result.output.first)

    #expect(try gray(atX: 15, y: 10, in: image) < 0.1)
    #expect(try gray(atX: 2, y: 10, in: image) > 0.9)
  }

  @Test func invalidConfigurationAndUnrepresentableGeometryFailDeterministically() throws {
    #expect(throws: SolidPostScript.Error.configurationError) {
      _ = try PlutoVGImageTarget(pixelWidth: 0, pixelHeight: 10).makeRenderer()
    }

    let target = PlutoVGImageTarget(pixelWidth: 10, pixelHeight: 10)
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
      try renderer.process(
        GraphicsEvent(operation: .paint(.fill(.winding)), before: state, after: state)
      )
    }
    renderer.abort()
  }

  @Test func abortReleasesTheActivePageAndRejectsFurtherEvents() throws {
    let renderer = try PlutoVGImageTarget(pixelWidth: 10, pixelHeight: 10).makeRenderer()
    renderer.abort()
    #expect(renderer.pages.isEmpty)

    let state = GraphicsStateSnapshot(
      matrix: .identity,
      path: GraphicsPath(),
      clip: GraphicsClip(imageableBounds: GraphicsRect(x: 0, y: 0, width: 10, height: 10)),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )
    #expect(throws: SolidPostScript.Error.ioError) {
      try renderer.process(GraphicsEvent(operation: .paint(.stroke), before: state, after: state))
    }
  }

  @Test func concurrentRendersUseIndependentNativeState() async throws {
    let environment = InterpreterEnvironment()
    async let black = Interpreter.render(
      content: "0 0 moveto 20 0 lineto 20 20 lineto 0 20 lineto closepath fill showpage",
      to: PlutoVGImageTarget(pixelWidth: 20, pixelHeight: 20),
      environment: environment
    )
    async let gray = Interpreter.render(
      content: "0.5 setgray 0 0 moveto 20 0 lineto 20 20 lineto 0 20 lineto closepath fill showpage",
      to: PlutoVGImageTarget(pixelWidth: 20, pixelHeight: 20),
      environment: environment
    )
    let (blackResult, grayResult) = try await (black, gray)
    let blackImage = try #require(blackResult.output.first)
    let grayImage = try #require(grayResult.output.first)

    #expect(try self.gray(atX: 10, y: 10, in: blackImage) < 0.1)
    #expect(try self.gray(atX: 10, y: 10, in: grayImage).isApproximatelyEqual(to: 0.5, tolerance: 0.05))
  }

  @Test func deviceColorsRectanglesImagesAndCopyPageRender() async throws {
    let program = """
    0 0 1 setrgbcolor 0 10 20 10 rectfill
    20 10 scale
    2 1 8 [2 0 0 1 0 0] <ff000000ff00> false 3 colorimage
    copypage showpage
    """
    let result = try await Interpreter.render(
      content: program,
      to: PlutoVGImageTarget(pixelWidth: 20, pixelHeight: 20)
    )

    #expect(result.output.count == 2)
    let copied = try #require(result.output.first)
    let erased = try #require(result.output.last)
    #expect(try rgb(atX: 5, y: 15, in: copied).red > 0.9)
    #expect(try rgb(atX: 15, y: 15, in: copied).green > 0.9)
    #expect(try rgb(atX: 10, y: 5, in: copied).blue > 0.9)
    #expect(try gray(atX: 10, y: 10, in: erased) > 0.9)
  }

  #if canImport(CoreGraphics)
  @Test func coreGraphicsAndPlutoVGAgreeAwayFromAntialiasedEdges() async throws {
    let program = "0.25 setgray 5 5 moveto 35 5 lineto 35 35 lineto 5 35 lineto closepath fill showpage"
    let pluto = try await Interpreter.render(
      content: program,
      to: PlutoVGImageTarget(pixelWidth: 40, pixelHeight: 40)
    )
    let coreGraphics = try await Interpreter.render(
      content: program,
      to: CoreGraphicsImageTarget(pixelWidth: 40, pixelHeight: 40)
    )
    let plutoImage = try #require(pluto.output.first)
    let coreGraphicsImage = try #require(coreGraphics.output.first)

    #expect(try gray(atX: 20, y: 20, in: plutoImage).isApproximatelyEqual(to: 0.25, tolerance: 0.05))
    #expect(try gray(atX: 20, y: 20, in: coreGraphicsImage).isApproximatelyEqual(to: 0.25, tolerance: 0.05))
  }
  #endif

  private func gray(atX x: Int, y: Int, in image: RasterImage) throws -> Double {
    let offset = y * image.bytesPerRow + x * 4
    guard x >= 0, x < image.width, y >= 0, y < image.height, offset + 3 < image.data.count else {
      throw SolidPostScript.Error.rangeCheck
    }
    return Double(image.data[offset]) / 255
  }

  private func red(atX x: Int, y: Int, in image: RasterImage) throws -> Double {
    Double(image.data[y * image.bytesPerRow + x * 4]) / 255
  }

  private func blue(atX x: Int, y: Int, in image: RasterImage) throws -> Double {
    Double(image.data[y * image.bytesPerRow + x * 4 + 2]) / 255
  }

  private func alpha(atX x: Int, y: Int, in image: RasterImage) throws -> Double {
    let offset = y * image.bytesPerRow + x * 4
    guard x >= 0, x < image.width, y >= 0, y < image.height, offset + 3 < image.data.count else {
      throw SolidPostScript.Error.rangeCheck
    }
    return Double(image.data[offset + 3]) / 255
  }

  private func rgb(
    atX x: Int,
    y: Int,
    in image: RasterImage
  ) throws -> (red: Double, green: Double, blue: Double) {
    let offset = y * image.bytesPerRow + x * 4
    guard x >= 0, x < image.width, y >= 0, y < image.height, offset + 3 < image.data.count else {
      throw SolidPostScript.Error.rangeCheck
    }
    return (
      Double(image.data[offset]) / 255,
      Double(image.data[offset + 1]) / 255,
      Double(image.data[offset + 2]) / 255
    )
  }

  #if canImport(CoreGraphics)
  private func gray(atX x: Int, y: Int, in image: CGImage) throws -> Double {
    let provider = try #require(image.dataProvider)
    let data = try #require(provider.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    let offset = y * image.bytesPerRow + x * 4
    return Double(bytes[offset]) / 255
  }
  #endif
}

private extension Double {
  func isApproximatelyEqual(to other: Double, tolerance: Double) -> Bool {
    abs(self - other) <= tolerance
  }
}
