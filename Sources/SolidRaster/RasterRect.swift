import Foundation

/// An axis-aligned rectangle in raster coordinate space.
public struct RasterRect: Sendable, Hashable {
  /// The minimum horizontal coordinate.
  public var x: Double
  /// The minimum vertical coordinate.
  public var y: Double
  /// The width.
  public var width: Double
  /// The height.
  public var height: Double

  /// Creates a rectangle.
  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// The maximum horizontal coordinate.
  public var maxX: Double { x + width }
  /// The maximum vertical coordinate.
  public var maxY: Double { y + height }
}
