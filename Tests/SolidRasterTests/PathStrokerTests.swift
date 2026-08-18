import SolidRaster
import Testing

@Suite struct PathStrokerTests {
  @Test func squareCapExtendsHalfWidth() throws {
    let path = RasterPath(elements: [
      .move(to: RasterPoint(x: 4, y: 8)),
      .line(to: RasterPoint(x: 12, y: 8)),
    ])
    var canvas = try RasterCanvas(width: 16, height: 16)
    try canvas.stroke(
      path,
      style: RasterStrokeStyle(width: 4, cap: .square),
      paint: .solid(.black)
    )
    let image = try canvas.finish()
    #expect(image.data[8 * image.bytesPerRow + 2 * 4] == 0)
    #expect(image.data[8 * image.bytesPerRow + 13 * 4] == 0)
    #expect(image.data[8 * image.bytesPerRow + 1 * 4] == 255)
  }

  @Test func dashCreatesAlternatingPaintedSegments() throws {
    let path = RasterPath(elements: [
      .move(to: RasterPoint(x: 2, y: 4)),
      .line(to: RasterPoint(x: 14, y: 4)),
    ])
    var canvas = try RasterCanvas(width: 16, height: 8)
    try canvas.stroke(
      path,
      style: RasterStrokeStyle(width: 2, dash: [3, 3]),
      paint: .solid(.black)
    )
    let image = try canvas.finish()
    #expect(image.data[4 * image.bytesPerRow + 3 * 4] == 0)
    #expect(image.data[4 * image.bytesPerRow + 6 * 4] == 255)
    #expect(image.data[4 * image.bytesPerRow + 9 * 4] == 0)
  }

  @Test func roundJoinCoversOuterCorner() throws {
    let path = RasterPath(elements: [
      .move(to: RasterPoint(x: 3, y: 12)),
      .line(to: RasterPoint(x: 8, y: 7)),
      .line(to: RasterPoint(x: 13, y: 12)),
    ])
    var canvas = try RasterCanvas(width: 16, height: 16)
    try canvas.stroke(
      path,
      style: RasterStrokeStyle(width: 4, join: .round),
      paint: .solid(.black)
    )
    let image = try canvas.finish()
    #expect(image.data[6 * image.bytesPerRow + 8 * 4] < 255)
  }
}
