import Foundation

/// Package-scoped vector geometry shared by PostScript semantics and raster rendering.
package enum RasterPathGeometry {
  /// Returns a path containing only moves, lines, and closes.
  package static func flattened(
    _ path: RasterPath,
    flatness: Double,
    limit: Int = RasterLimits.default.maximumPathElements
  ) throws(RasterError) -> RasterPath {
    let result = try PathFlattener.flatten(path, flatness: flatness)
    var builder = RasterPath.Builder(limit: limit)
    for subpath in result.subpaths {
      guard let first = subpath.points.first else { continue }
      try builder.move(to: first)
      for point in subpath.points.dropFirst() {
        try builder.line(to: point)
      }
      if subpath.isClosed {
        try builder.close()
      }
    }
    return builder.finish()
  }

  /// Returns the geometric stroke outline for a path.
  package static func stroked(
    _ path: RasterPath,
    style: RasterStrokeStyle,
    transform: RasterAffineTransform,
    flatness: Double
  ) throws(RasterError) -> RasterPath {
    try PathStroker.stroke(path, style: style, transform: transform, flatness: flatness)
  }
}
