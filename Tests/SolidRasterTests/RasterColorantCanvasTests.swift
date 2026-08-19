import Testing

@testable import SolidRaster

@Suite
struct RasterColorantCanvasTests {
  @Test func knockoutClearsUnspecifiedColorantsAndOverprintPreservesThem() throws {
    let path = RasterPath(elements: [
      .move(to: RasterPoint(x: 0, y: 0)),
      .line(to: RasterPoint(x: 2, y: 0)),
      .line(to: RasterPoint(x: 2, y: 1)),
      .line(to: RasterPoint(x: 0, y: 1)),
      .close,
    ])
    var canvas = try RasterColorantCanvas(width: 2, height: 1, colorants: ["Cyan", "Spot"])
    try canvas.fill(path, rule: .winding, paint: RasterColorantPaint(tints: ["Spot": 1]))
    try canvas.fill(
      path,
      rule: .winding,
      paint: RasterColorantPaint(tints: ["Cyan": 0.5], overprintsUnspecifiedColorants: true)
    )
    let planes = try canvas.finish()

    #expect(Array(planes[0].mask.data) == [128, 128])
    #expect(Array(planes[1].mask.data) == [255, 255])
  }

  @Test func nonePaintLeavesEveryPlaneUnchanged() throws {
    let path = RasterPath(elements: [
      .move(to: RasterPoint(x: 0, y: 0)),
      .line(to: RasterPoint(x: 1, y: 0)),
      .line(to: RasterPoint(x: 1, y: 1)),
      .line(to: RasterPoint(x: 0, y: 1)),
      .close,
    ])
    var canvas = try RasterColorantCanvas(width: 1, height: 1, colorants: ["Black"])
    try canvas.fill(
      path,
      rule: .winding,
      paint: RasterColorantPaint(tints: [:], paintsNothing: true)
    )
    #expect(Array(try canvas.finish()[0].mask.data) == [0])
  }
}
