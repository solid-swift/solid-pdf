import Foundation

/// A failure reported while negotiating target page geometry.
public enum GraphicsPageDeviceError: Swift.Error, Sendable, Equatable {
  /// The requested geometry or resolution is invalid.
  case invalidConfiguration
  /// The resulting page exceeds the provider's configured limits.
  case limitExceeded
}
