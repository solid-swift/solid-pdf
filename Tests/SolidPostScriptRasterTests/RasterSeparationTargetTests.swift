import Testing

@testable import SolidPostScript
@testable import SolidPostScriptRaster

@Suite
struct RasterSeparationTargetTests {
  @Test func targetPreservesTypedPageOutputAndCompositePreview() async throws {
    let result = try await Interpreter.render(
      content: "0 setgray 0 0 2 2 rectfill showpage",
      to: RasterSeparationTarget(
        deviceDescriptor: GraphicsDeviceDescriptor(
          mediaBounds: GraphicsRect(x: 0, y: 0, width: 2, height: 2),
          imageableBounds: GraphicsRect(x: 0, y: 0, width: 2, height: 2),
          horizontalResolution: 72,
          verticalResolution: 72,
          defaultMatrix: .identity
        )
      )
    )

    let page = try #require(result.output.first)
    #expect(page.compositePreview.width == 2)
    #expect(page.compositePreview.height == 2)
    #expect(page.device.descriptor.colorants.processModel == .deviceCMYK)
  }
}
