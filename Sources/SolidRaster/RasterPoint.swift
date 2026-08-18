import Foundation

/// A point in raster coordinate space.
public struct RasterPoint: Sendable, Hashable {
  /// The horizontal coordinate.
  public var x: Double
  /// The vertical coordinate.
  public var y: Double

  /// Creates a point.
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}
