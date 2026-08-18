import SolidRaster
import Testing

@Suite struct GrayRasterizerTests {
  @Test func fillsRectangleWithExactInteriorCoverage() throws {
    var builder = RasterPath.Builder()
    try builder.move(to: RasterPoint(x: 2, y: 2))
    try builder.line(to: RasterPoint(x: 6, y: 2))
    try builder.line(to: RasterPoint(x: 6, y: 6))
    try builder.line(to: RasterPoint(x: 2, y: 6))
    try builder.close()
    let path = builder.finish()
    var canvas = try RasterCanvas(width: 8, height: 8)
    try canvas.fill(path, rule: .winding, paint: .solid(.black))
    let image = try canvas.finish()
    let interior = (3 * image.bytesPerRow) + (3 * 4)
    #expect(image.data[interior] == 0)
    #expect(image.data[interior + 3] == 255)
    let exterior = (1 * image.bytesPerRow) + (1 * 4)
    #expect(image.data[exterior] == 255)
  }

  @Test func evenOddMakesNestedContourHole() throws {
    let elements: [RasterPath.Element] = [
      .move(to: RasterPoint(x: 1, y: 1)),
      .line(to: RasterPoint(x: 7, y: 1)),
      .line(to: RasterPoint(x: 7, y: 7)),
      .line(to: RasterPoint(x: 1, y: 7)),
      .close,
      .move(to: RasterPoint(x: 3, y: 3)),
      .line(to: RasterPoint(x: 5, y: 3)),
      .line(to: RasterPoint(x: 5, y: 5)),
      .line(to: RasterPoint(x: 3, y: 5)),
      .close,
    ]
    var canvas = try RasterCanvas(width: 8, height: 8)
    try canvas.fill(RasterPath(elements: elements), rule: .evenOdd, paint: .solid(.black))
    let image = try canvas.finish()
    #expect(image.data[2 * image.bytesPerRow + 2 * 4] == 0)
    #expect(image.data[4 * image.bytesPerRow + 4 * 4] == 255)
  }
}
