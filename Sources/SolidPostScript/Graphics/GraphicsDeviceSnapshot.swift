import Foundation

/// Immutable language-visible characteristics of the current graphics device.
public struct GraphicsDeviceSnapshot: Sendable, Hashable {
  /// The installed device's identity.
  public let identifier: GraphicsDeviceIdentifier
  /// The installed device's kind.
  public let kind: GraphicsDeviceKind
  /// Geometry and rendering characteristics of the device.
  public let descriptor: GraphicsDeviceDescriptor
  /// The number of prior `showpage` executions since activation.
  public let pageNumber: Int
  /// The configured copy count, or `nil` when `#copies` is consulted.
  public let numberOfCopies: Int?
  /// The trapping state owned by this device and page.
  public let trapping: GraphicsTrappingSnapshot

  /// Creates a device snapshot.
  public init(
    identifier: GraphicsDeviceIdentifier,
    kind: GraphicsDeviceKind,
    descriptor: GraphicsDeviceDescriptor,
    pageNumber: Int,
    numberOfCopies: Int?,
    trapping: GraphicsTrappingSnapshot = .disabled
  ) {
    self.identifier = identifier
    self.kind = kind
    self.descriptor = descriptor
    self.pageNumber = pageNumber
    self.numberOfCopies = numberOfCopies
    self.trapping = trapping
  }

  /// The default virtual Letter page device.
  public static let letter = Self(
    identifier: GraphicsDeviceIdentifier(),
    kind: .page,
    descriptor: .letter,
    pageNumber: 0,
    numberOfCopies: 1
  )
}
