import SolidRaster
import SolidRasterBenchmarkSupport
import Testing

@Suite struct RasterBenchmarkFixturesTests {
  @Test func pathFixturesHaveStableShapes() throws {
    let surface = try RasterBenchmarkFixtures.surfacePath()
    let cubic = try RasterBenchmarkFixtures.cubicPath()
    let clip = try RasterBenchmarkFixtures.deepClip()

    #expect(surface.elements.count == 5)
    #expect(cubic.elements.count == 1_001)
    #expect(clip.constraints.count == 32)
  }

  @Test func imageFixtureHasStableDimensionsAndStorage() throws {
    let image = try RasterBenchmarkFixtures.largeImage()

    #expect(image.width == 3_840)
    #expect(image.height == 2_160)
    #expect(image.bytesPerRow == image.width * 4)
    #expect(image.data.count == image.bytesPerRow * image.height)
    #expect(image.pixelFormat == .rgba8Unorm)
  }
}
