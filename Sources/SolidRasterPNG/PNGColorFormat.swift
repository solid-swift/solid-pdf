/// The PNG output color format.
public enum PNGColorFormat: Sendable, Hashable {
  /// Opaque RGB output, flattening source alpha against the configured background.
  case rgb
  /// Straight-alpha RGBA output.
  case rgba
}
