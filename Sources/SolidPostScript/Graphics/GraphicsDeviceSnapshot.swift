import Foundation

/// Immutable language-visible characteristics of the current graphics device.
public struct GraphicsDeviceSnapshot: Sendable, Hashable {
  /// The installed device's identity.
  public let identifier: GraphicsDeviceIdentifier
  /// Stable identity of the physical output device across installations.
  public let outputDeviceIdentifier: GraphicsOutputDeviceIdentifier
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
  /// Whether Device color spaces are remapped through Default ColorSpace resources.
  public let usesCIEColor: Bool
  /// The selected or deferred physical input medium.
  public let mediaSelection: GraphicsMediaSelection
  /// Physical placement for the current page side.
  public let placement: GraphicsPagePlacement
  /// Physical page-delivery behavior.
  public let delivery: GraphicsPageDeliveryConfiguration

  /// Creates a device snapshot.
  public init(
    identifier: GraphicsDeviceIdentifier,
    outputDeviceIdentifier: GraphicsOutputDeviceIdentifier = .virtual,
    kind: GraphicsDeviceKind,
    descriptor: GraphicsDeviceDescriptor,
    pageNumber: Int,
    numberOfCopies: Int?,
    trapping: GraphicsTrappingSnapshot = .disabled,
    usesCIEColor: Bool = false,
    mediaSelection: GraphicsMediaSelection = .virtual,
    placement: GraphicsPagePlacement = .simplex,
    delivery: GraphicsPageDeliveryConfiguration = .virtual
  ) {
    self.identifier = identifier
    self.outputDeviceIdentifier = outputDeviceIdentifier
    self.kind = kind
    self.descriptor = descriptor
    self.pageNumber = pageNumber
    self.numberOfCopies = numberOfCopies
    self.trapping = trapping
    self.usesCIEColor = usesCIEColor
    self.mediaSelection = mediaSelection
    self.placement = placement
    self.delivery = delivery
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
