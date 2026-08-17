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

  private func gray(atX x: Int, y: Int, in image: CGImage) throws -> Double {
    let provider = try #require(image.dataProvider)
    let data = try #require(provider.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    let offset = y * image.bytesPerRow + x * 4
    return Double(bytes[offset]) / 255
  }
}
#endif
