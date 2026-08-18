import Foundation
import SolidRaster

private func measure(_ label: String, iterations: Int = 5, _ body: () throws -> Void) rethrows {
  var samples: [Duration] = []
  let clock = ContinuousClock()
  for _ in 0..<iterations {
    let start = clock.now
    try body()
    samples.append(start.duration(to: clock.now))
  }
  samples.sort()
  print("\(label): \(samples[samples.count / 2]) median")
}

private func cubicFixture() throws -> RasterPath {
  var builder = RasterPath.Builder(limit: 4_001)
  try builder.move(to: RasterPoint(x: 16, y: 384))
  for index in 0..<1_000 {
    let x = 16 + Double(index % 50) * 12
    let y = 16 + Double(index / 50) * 36
    try builder.cubic(
      control1: RasterPoint(x: x + 3, y: y - 12),
      control2: RasterPoint(x: x + 9, y: y + 12),
      end: RasterPoint(x: x + 12, y: y)
    )
  }
  return builder.finish()
}

let path = try cubicFixture()
try measure("1000 cubic fill") {
  var canvas = try RasterCanvas(width: 640, height: 800)
  try canvas.fill(path, rule: .winding, paint: .solid(.black))
  _ = try canvas.finish(pixelFormat: .rgba8UnormPremultiplied)
}

try measure("dashed stroke") {
  var canvas = try RasterCanvas(width: 640, height: 800)
  try canvas.stroke(
    path,
    style: RasterStrokeStyle(width: 3, cap: .round, join: .round, dash: [8, 3, 2, 3]),
    paint: .solid(RasterColor(red: 0.1, green: 0.4, blue: 0.8))
  )
  _ = try canvas.finish(pixelFormat: .rgba8UnormPremultiplied)
}
