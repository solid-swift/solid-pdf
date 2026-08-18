import Foundation
import SolidRaster
import Testing

@Suite struct RasterGeometryTests {
  @Test func matrixRoundTrip() throws {
    let matrix = RasterAffineTransform(a: 2, b: 0.5, c: -0.25, d: 3, tx: 7, ty: -2)
    let inverse = try #require(matrix.inverted)
    let point = RasterPoint(x: 11, y: 13)
    let restored = inverse.transform(matrix.transform(point))
    #expect(abs(restored.x - point.x) < 1e-10)
    #expect(abs(restored.y - point.y) < 1e-10)
  }

  @Test func builderIsBounded() throws {
    var builder = RasterPath.Builder(limit: 1)
    try builder.move(to: RasterPoint(x: 0, y: 0))
    #expect(throws: RasterError.limitExceeded) {
      try builder.line(to: RasterPoint(x: 1, y: 1))
    }
  }

  @Test func imageValidatesBackingStorage() {
    #expect(throws: RasterError.invalidImage) {
      try RasterImage(
        width: 2,
        height: 2,
        bytesPerRow: 8,
        pixelFormat: .rgba8Unorm,
        data: Data(repeating: 0, count: 15)
      )
    }
  }
}
