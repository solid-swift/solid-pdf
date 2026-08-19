#if canImport(CoreGraphics)
import CoreGraphics
import Testing

import SolidPostScript
import SolidPostScriptCoreGraphics

@Suite
struct CoreGraphicsImageTargetTests {

  @Test func showPageProducesIndependentImagesAndDiscardsTheFinalPage() async throws {
    let result = try await Interpreter.render(
      content: "showpage showpage 0 setgray 0 0 moveto 10 10 lineto stroke",
      to: CoreGraphicsImageTarget(pixelWidth: 40, pixelHeight: 30)
    )

    #expect(result.output.count == 2)
    #expect(result.output.allSatisfy { $0.width == 40 && $0.height == 30 })
  }

  @Test func fillsTransformsCurvesAndClippingRenderFromSnapshots() async throws {
    let program = """
    newpath 0 0 moveto 25 0 lineto 25 50 lineto 0 50 lineto closepath clip
    0 setgray
    10 0 translate
    newpath -10 5 moveto 35 5 35 45 35 45 curveto -10 45 lineto closepath fill
    showpage
    """
    let result = try await Interpreter.render(
      content: program,
      to: CoreGraphicsImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let image = try #require(result.output.first)

    #expect(try gray(atX: 12, y: 25, in: image) < 0.1)
    #expect(try gray(atX: 40, y: 25, in: image) > 0.9)
  }

  @Test func strokeStateAndErasePageAreApplied() async throws {
    let stroked = try await Interpreter.render(
      content: "0 setgray 8 setlinewidth 25 2 moveto 25 48 lineto stroke showpage",
      to: CoreGraphicsImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let strokeImage = try #require(stroked.output.first)
    #expect(try gray(atX: 25, y: 25, in: strokeImage) < 0.1)
    #expect(try gray(atX: 5, y: 25, in: strokeImage) > 0.9)

    let erased = try await Interpreter.render(
      content: "0 setgray 0 0 moveto 50 0 lineto 50 50 lineto 0 50 lineto closepath fill erasepage showpage",
      to: CoreGraphicsImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let erasedImage = try #require(erased.output.first)
    #expect(try gray(atX: 25, y: 25, in: erasedImage) > 0.9)
  }

  @Test func singularStrokeMatrixProducesNoVisibleMark() async throws {
    let result = try await Interpreter.render(
      content: "0 setgray 0 0 moveto 40 40 lineto [1 0 0 0 0 0] setmatrix stroke showpage",
      to: CoreGraphicsImageTarget(pixelWidth: 50, pixelHeight: 50)
    )
    let image = try #require(result.output.first)
    #expect(try gray(atX: 20, y: 20, in: image) > 0.9)
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
      to: CoreGraphicsImageTarget(pixelWidth: 20, pixelHeight: 20)
    )

    #expect(result.output.count == 2)
    let copied = try #require(result.output.first)
    let erased = try #require(result.output.last)
    #expect(try rgb(atX: 5, y: 15, in: copied).red > 0.9)
    #expect(try rgb(atX: 15, y: 15, in: copied).green > 0.9)
    #expect(try rgb(atX: 10, y: 5, in: copied).blue > 0.9)
    #expect(try gray(atX: 10, y: 10, in: erased) > 0.9)
  }

  @Test func namedColorsAndGeneralizedImagesUseCoreGraphicsColorSessions() async throws {
    let result = try await Interpreter.render(
      content: """
      [/Separation /Spot /DeviceRGB {dup 1 exch sub 0}] setcolorspace
      .25 setcolor 0 10 20 10 rectfill
      << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8
         /ImageMatrix [.05 0 0 .1 0 0] /Decode [0 1] /DataSource <40>
      >> image showpage
      """,
      to: CoreGraphicsImageTarget(pixelWidth: 20, pixelHeight: 20)
    )
    let image = try #require(result.output.first)
    let vector = try rgb(atX: 10, y: 5, in: image)
    let sampled = try rgb(atX: 10, y: 15, in: image)
    #expect(abs(vector.red - 0.25) < 0.03)
    #expect(abs(vector.green - 0.75) < 0.03)
    #expect(abs(sampled.red - 64.0 / 255.0) < 0.03)
    #expect(abs(sampled.green - 191.0 / 255.0) < 0.03)
  }

  @Test func outputRetainsTheConfiguredCoreGraphicsDestinationSpace() async throws {
    let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let result = try await Interpreter.render(
      content: "1 0 0 setrgbcolor 0 0 10 10 rectfill showpage",
      to: CoreGraphicsImageTarget(
        pixelWidth: 10,
        pixelHeight: 10,
        destinationColorSpace: displayP3
      )
    )
    #expect(try #require(result.output.first).colorSpace == displayP3)
  }

  @Test func imageMasksUseTheSameStagingSpaceAsVectorPaints() async throws {
    let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let result = try await Interpreter.render(
      content: """
      1 .2 .1 setrgbcolor 0 0 10 10 rectfill showpage
      1 .2 .1 setrgbcolor 10 10 scale 1 1 true [1 0 0 1 0 0] <80> imagemask showpage
      """,
      to: CoreGraphicsImageTarget(
        pixelWidth: 10,
        pixelHeight: 10,
        destinationColorSpace: displayP3
      )
    )
    let vector = try rgb(atX: 5, y: 5, in: #require(result.output.first))
    let mask = try rgb(atX: 5, y: 5, in: #require(result.output.last))
    #expect(abs(vector.red - mask.red) < 0.02)
    #expect(abs(vector.green - mask.green) < 0.02)
    #expect(abs(vector.blue - mask.blue) < 0.02)
  }

  private func gray(atX x: Int, y: Int, in image: CGImage) throws -> Double {
    let provider = try #require(image.dataProvider)
    let data = try #require(provider.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    let offset = y * image.bytesPerRow + x * 4
    return Double(bytes[offset]) / 255
  }

  private func rgb(
    atX x: Int,
    y: Int,
    in image: CGImage
  ) throws -> (red: Double, green: Double, blue: Double) {
    let provider = try #require(image.dataProvider)
    let data = try #require(provider.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    let offset = y * image.bytesPerRow + x * 4
    return (Double(bytes[offset]) / 255, Double(bytes[offset + 1]) / 255, Double(bytes[offset + 2]) / 255)
  }
}
#endif
