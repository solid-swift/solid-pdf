import Foundation

/// A stable identity for one physical or virtual output device across page-device installations.
public struct GraphicsOutputDeviceIdentifier: Sendable, Hashable {
  private let rawValue: UUID

  /// Creates a new output-device identity.
  public init() {
    self.rawValue = UUID()
  }

  init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  /// The stable identity used by source-compatible virtual page devices.
  public static let virtual = Self(rawValue: UUID(uuid: (
    0, 0, 0, 0,
    0, 0,
    0, 0,
    0, 0,
    0, 0, 0, 0, 0, 1
  )))
}
