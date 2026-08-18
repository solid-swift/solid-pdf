import Foundation
import SolidRaster
import Testing

@Suite struct RasterImageDrawingTests {
  @Test func nearestDrawPreservesSourcePixels() throws {
    let source = try RasterImage(
      width: 2,
      height: 1,
      bytesPerRow: 8,
      pixelFormat: .rgba8Unorm,
      data: Data([255, 0, 0, 255, 0, 0, 255, 255])
    )
    var canvas = try RasterCanvas(width: 4, height: 2)
    try canvas.draw(
      source,
      transform: RasterAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0)
    )
    let image = try canvas.finish()
    #expect(Array(image.data[0..<4]) == [255, 0, 0, 255])
    #expect(Array(image.data[8..<12]) == [0, 0, 255, 255])
  }

  @Test func linearDrawInterpolatesColors() throws {
    let source = try RasterImage(
      width: 2,
      height: 1,
      bytesPerRow: 8,
      pixelFormat: .rgba8Unorm,
      data: Data([0, 0, 0, 255, 255, 255, 255, 255])
    )
    var canvas = try RasterCanvas(width: 4, height: 1)
    try canvas.draw(
      source,
      transform: RasterAffineTransform(a: 2, b: 0, c: 0, d: 1, tx: 0, ty: 0),
      interpolation: .linear
    )
    let image = try canvas.finish()
    #expect(image.data[4] > 0)
    #expect(image.data[4] < 255)
  }

  @Test func premultipliedOutputRetainsAlphaEncoding() throws {
    let canvas = try RasterCanvas(width: 1, height: 1, background: RasterColor(red: 1, green: 0, blue: 0, alpha: 0.5))
    let image = try canvas.finish(pixelFormat: .rgba8UnormPremultiplied)
    #expect(image.data[0] == 128)
    #expect(image.data[3] == 128)
  }
}
