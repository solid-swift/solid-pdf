import Foundation

/// The byte organization of a portable raster image.
public enum RasterPixelFormat: Sendable, Hashable {
  /// Straight-alpha normalized 8-bit red, green, blue, and alpha components.
  case rgba8Unorm
  /// Premultiplied normalized 8-bit red, green, blue, and alpha components.
  case rgba8UnormPremultiplied
}
