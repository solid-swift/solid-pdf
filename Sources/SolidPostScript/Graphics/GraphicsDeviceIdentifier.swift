import Foundation

/// An opaque identity for one installed PostScript graphics device.
public struct GraphicsDeviceIdentifier: Sendable, Hashable {
  private let rawValue: UUID

  /// Creates a new stable device identity.
  public init() {
    self.rawValue = UUID()
  }

  init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}
