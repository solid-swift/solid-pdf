import SolidRaster
import Testing

@Suite struct RasterGradientMeshTests {
  @Test func triangleInterpolatesColorThroughCoverage() throws {
    var canvas = try RasterCanvas(width: 8, height: 8)
    let mesh = RasterGradientMesh(triangles: [
      RasterGradientTriangle(
        first: RasterGradientVertex(position: RasterPoint(x: 0, y: 0), color: .init(red: 1, green: 0, blue: 0)),
        second: RasterGradientVertex(position: RasterPoint(x: 8, y: 0), color: .init(red: 0, green: 1, blue: 0)),
        third: RasterGradientVertex(position: RasterPoint(x: 0, y: 8), color: .init(red: 0, green: 0, blue: 1))
      )
    ])
    try canvas.paint(mesh)
    let image = try canvas.finish()
    let offset = (2 * image.bytesPerRow) + 2 * 4
    #expect(image.data[offset] < 255)
    #expect(image.data[offset + 1] < 255)
    #expect(image.data[offset + 2] < 255)
    #expect(image.data[offset + 3] == 255)
  }

  @Test func triangleLimitFailsBeforePainting() throws {
    var canvas = try RasterCanvas(
      width: 2,
      height: 2,
      limits: RasterLimits(maximumScratchBytes: 1)
    )
    let vertex = RasterGradientVertex(position: RasterPoint(x: 0, y: 0), color: .black)
    #expect(throws: RasterError.limitExceeded) {
      try canvas.paint(RasterGradientMesh(triangles: [
        RasterGradientTriangle(first: vertex, second: vertex, third: vertex)
      ]))
    }
  }
}
