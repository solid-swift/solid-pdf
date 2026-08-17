import Foundation

/// The byte organization of a portable raster image.
public enum RasterPixelFormat: Sendable, Hashable {
  /// Four straight-alpha, normalized 8-bit components in red, green, blue, alpha order.
  case rgba8Unorm
}
