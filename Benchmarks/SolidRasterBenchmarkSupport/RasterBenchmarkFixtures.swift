import Foundation
import SolidRaster

/// Deterministic fixtures shared by native raster benchmarks.
public enum RasterBenchmarkFixtures {
  /// Width of the path-oriented benchmark surface.
  public static let pathSurfaceWidth = 640

  /// Height of the path-oriented benchmark surface.
  public static let pathSurfaceHeight = 800

  /// Width of the image-oriented benchmark surface.
  public static let imageWidth = 3_840

  /// Height of the image-oriented benchmark surface.
  public static let imageHeight = 2_160

  /// A path containing one thousand cubic segments.
  public static func cubicPath() throws -> RasterPath {
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

  /// A rectangle covering the complete path-oriented surface.
  public static func surfacePath() throws -> RasterPath {
    try rectangle(
      RasterRect(
        x: 0,
        y: 0,
        width: Double(pathSurfaceWidth),
        height: Double(pathSurfaceHeight)
      )
    )
  }

  /// A deterministic stack of nested rectangular clipping constraints.
  public static func deepClip(constraintCount: Int = 32) throws -> RasterClip {
    precondition(constraintCount >= 0)
    let bounds = RasterRect(
      x: 0,
      y: 0,
      width: Double(pathSurfaceWidth),
      height: Double(pathSurfaceHeight)
    )
    let constraints = try (0..<constraintCount).map { index in
      let inset = Double(index + 1) * 3
      return RasterClipConstraint(
        path: try rectangle(
          RasterRect(
            x: inset,
            y: inset,
            width: max(0, bounds.width - inset * 2),
            height: max(0, bounds.height - inset * 2)
          )
        ),
        rule: .winding
      )
    }
    return RasterClip(imageableBounds: bounds, constraints: constraints)
  }

  /// An opaque deterministic 8-megapixel RGBA image.
  public static func largeImage() throws -> RasterImage {
    let bytesPerRow = imageWidth * 4
    var data = Data(count: bytesPerRow * imageHeight)
    data.withUnsafeMutableBytes { rawBuffer in
      guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
      for y in 0..<imageHeight {
        for x in 0..<imageWidth {
          let offset = y * bytesPerRow + x * 4
          bytes[offset] = UInt8(truncatingIfNeeded: x)
          bytes[offset + 1] = UInt8(truncatingIfNeeded: y)
          bytes[offset + 2] = UInt8(truncatingIfNeeded: x ^ y)
          bytes[offset + 3] = 255
        }
      }
    }
    return try RasterImage(
      width: imageWidth,
      height: imageHeight,
      bytesPerRow: bytesPerRow,
      pixelFormat: .rgba8Unorm,
      data: data
    )
  }

  /// The standard dashed-stroke style used by path benchmarks.
  public static let dashedStrokeStyle = RasterStrokeStyle(
    width: 3,
    cap: .round,
    join: .round,
    dash: [8, 3, 2, 3]
  )

  private static func rectangle(_ rect: RasterRect) throws -> RasterPath {
    var builder = RasterPath.Builder(limit: 5)
    try builder.move(to: RasterPoint(x: rect.x, y: rect.y))
    try builder.line(to: RasterPoint(x: rect.maxX, y: rect.y))
    try builder.line(to: RasterPoint(x: rect.maxX, y: rect.maxY))
    try builder.line(to: RasterPoint(x: rect.x, y: rect.maxY))
    try builder.close()
    return builder.finish()
  }
}
