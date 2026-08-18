@testable import SolidRaster
import Testing

@Suite struct CoverageSpansTests {
  @Test func intersectsCoverageIntoReusableStorage() {
    let left = [
      CoverageSpan(x: 1, y: 0, length: 4, coverage: 255),
      CoverageSpan(x: 0, y: 1, length: 3, coverage: 128),
    ]
    let right = [
      CoverageSpan(x: 3, y: 0, length: 4, coverage: 128),
      CoverageSpan(x: 1, y: 1, length: 3, coverage: 128),
    ]
    var result = [CoverageSpan(x: 0, y: 0, length: 1, coverage: 1)]

    CoverageSpans.intersect(left.span, right.span, into: &result)

    #expect(result == [
      CoverageSpan(x: 3, y: 0, length: 2, coverage: 128),
      CoverageSpan(x: 1, y: 1, length: 2, coverage: 64),
    ])
  }

  @Test func recognizesOnlyIntegralAxisAlignedRectangles() {
    let rectangle = RasterPath(elements: [
      .move(to: RasterPoint(x: 2, y: 3)),
      .line(to: RasterPoint(x: 8, y: 3)),
      .line(to: RasterPoint(x: 8, y: 9)),
      .line(to: RasterPoint(x: 2, y: 9)),
      .close,
    ])
    let fractional = RasterPath(elements: [
      .move(to: RasterPoint(x: 2.5, y: 3)),
      .line(to: RasterPoint(x: 8, y: 3)),
      .line(to: RasterPoint(x: 8, y: 9)),
      .line(to: RasterPoint(x: 2.5, y: 9)),
      .close,
    ])

    #expect(CoverageSpans.integralRectangle(in: rectangle) == RasterRect(x: 2, y: 3, width: 6, height: 6))
    #expect(CoverageSpans.integralRectangle(in: fractional) == nil)
  }

  @Test func repeatedAndExtendedClipsPreserveRendering() throws {
    let outer = rectangle(x: 1, y: 1, width: 6, height: 6)
    let inner = rectangle(x: 3, y: 3, width: 2, height: 2)
    let initial = RasterClip(
      imageableBounds: RasterRect(x: 0, y: 0, width: 8, height: 8),
      constraints: [RasterClipConstraint(path: outer, rule: .winding)]
    )
    let extended = RasterClip(
      imageableBounds: initial.imageableBounds,
      constraints: initial.constraints + [RasterClipConstraint(path: inner, rule: .winding)]
    )
    var canvas = try RasterCanvas(width: 8, height: 8)
    try canvas.setClip(initial)
    try canvas.setClip(initial)
    try canvas.setClip(extended)
    try canvas.fill(outer, rule: .winding, paint: .solid(.black))
    let image = try canvas.finish()

    #expect(image.data[4 * image.bytesPerRow + 4 * 4] == 0)
    #expect(image.data[2 * image.bytesPerRow + 2 * 4] == 255)
  }

  private func rectangle(x: Double, y: Double, width: Double, height: Double) -> RasterPath {
    RasterPath(elements: [
      .move(to: RasterPoint(x: x, y: y)),
      .line(to: RasterPoint(x: x + width, y: y)),
      .line(to: RasterPoint(x: x + width, y: y + height)),
      .line(to: RasterPoint(x: x, y: y + height)),
      .close,
    ])
  }
}
