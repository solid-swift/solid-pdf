import Foundation

/// The kind of output device installed in a PostScript graphics state.
public enum GraphicsDeviceKind: Sendable, Hashable {
  /// A page-oriented output device.
  case page
  /// The no-output device installed by `nulldevice`.
  case null
}
