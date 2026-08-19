import Foundation

/// The actual settings selected for an installed page device.
public struct GraphicsPageDeviceConfiguration: Sendable, Hashable {
  /// The device identity assigned to this installation.
  public let identifier: GraphicsDeviceIdentifier
  /// The page size in default-user-space points.
  public let pageSize: GraphicsSize
  /// The optional asserted imaging bounds in default user space.
  public let imagingBoundingBox: GraphicsRect?
  /// The configured copy count, or `nil` to use `#copies`.
  public let numberOfCopies: Int?
  /// The installation-defined page-device name.
  public let name: String
  /// The realized target descriptor.
  public let descriptor: GraphicsDeviceDescriptor
  /// The realized process and named-colorant configuration.
  public let colorants: GraphicsColorantConfiguration
  /// Whether the installed device performs in-RIP trapping.
  public let trappingEnabled: Bool
  /// The installed type-specific trapping details.
  public let trappingDetails: GraphicsTrappingDetails
  /// Whether Device color spaces are remapped through Default ColorSpace resources.
  public let usesCIEColor: Bool

  /// Creates a page-device configuration.
  public init(
    identifier: GraphicsDeviceIdentifier,
    pageSize: GraphicsSize,
    imagingBoundingBox: GraphicsRect?,
    numberOfCopies: Int?,
    name: String,
    descriptor: GraphicsDeviceDescriptor,
    colorants: GraphicsColorantConfiguration = .compositeRGB,
    trappingEnabled: Bool = false,
    trappingDetails: GraphicsTrappingDetails = GraphicsTrappingDetails(),
    usesCIEColor: Bool = false
  ) {
    self.identifier = identifier
    self.pageSize = pageSize
    self.imagingBoundingBox = imagingBoundingBox
    self.numberOfCopies = numberOfCopies
    self.name = name
    self.descriptor = descriptor
    self.colorants = colorants
    self.trappingEnabled = trappingEnabled
    self.trappingDetails = trappingDetails
    self.usesCIEColor = usesCIEColor
  }
}
