import Testing

@testable import SolidRaster

@Suite
struct RasterRegionTests {
  @Test func pathRegionsIntersectAsVectors() throws {
    let first = try RasterRegion.path(
      rectangle(x: 0, y: 0, width: 10, height: 10),
      rule: .winding,
      flatness: 1
    )
    let second = try RasterRegion.path(
      rectangle(x: 5, y: 5, width: 10, height: 10),
      rule: .winding,
      flatness: 1
    )
    let overlap = try first.intersecting(second)

    #expect(!overlap.isEmpty)
    #expect(overlap.intersects(try RasterRegion.rectangle(RasterRect(x: 6, y: 6, width: 1, height: 1))))
    #expect(!overlap.intersects(try RasterRegion.rectangle(RasterRect(x: 1, y: 1, width: 1, height: 1))))
  }

  @Test func evenOddRegionsRemoveNestedInteriors() throws {
    let path = RasterPath(elements:
      rectangle(x: 0, y: 0, width: 10, height: 10).elements
        + rectangle(x: 2, y: 2, width: 6, height: 6).elements
    )
    let region = try RasterRegion.path(path, rule: .evenOdd, flatness: 1)

    #expect(region.intersects(try RasterRegion.rectangle(RasterRect(x: 1, y: 1, width: 0.5, height: 0.5))))
    #expect(!region.intersects(try RasterRegion.rectangle(RasterRect(x: 4, y: 4, width: 1, height: 1))))
  }

  @Test func flattenedGeometryUsesRequestedTolerance() throws {
    let curve = RasterPath(elements: [
      .move(to: RasterPoint(x: 0, y: 0)),
      .cubic(
        control1: RasterPoint(x: 0, y: 100),
        control2: RasterPoint(x: 100, y: 100),
        end: RasterPoint(x: 100, y: 0)
      ),
    ])

    let coarse = try RasterPathGeometry.flattened(curve, flatness: 20)
    let fine = try RasterPathGeometry.flattened(curve, flatness: 0.2)
    #expect(fine.elements.count > coarse.elements.count)
    #expect(!fine.elements.contains { if case .cubic = $0 { true } else { false } })
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
