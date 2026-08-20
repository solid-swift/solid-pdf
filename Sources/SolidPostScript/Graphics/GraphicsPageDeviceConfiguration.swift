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
  /// The stable output-device identity shared by compatible installations.
  public let outputDeviceIdentifier: GraphicsOutputDeviceIdentifier
  /// The output-device resource name, when selectable.
  public let outputDevice: String?
  /// The current input-media catalog.
  public let inputMedia: GraphicsMediaCatalog
  /// The normalized current media request.
  public let mediaRequest: GraphicsMediaRequest
  /// The actual or deferred media selection.
  public let mediaSelection: GraphicsMediaSelection
  /// The current output-destination catalog.
  public let outputDestinations: GraphicsOutputCatalog
  /// The language-visible output type request.
  public let outputType: Data?
  /// Physical placement for the current side.
  public let placement: GraphicsPagePlacement
  /// Physical delivery and roll-media behavior.
  public let delivery: GraphicsPageDeliveryConfiguration

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
    usesCIEColor: Bool = false,
    outputDeviceIdentifier: GraphicsOutputDeviceIdentifier = .virtual,
    outputDevice: String? = nil,
    inputMedia: GraphicsMediaCatalog = .empty,
    mediaRequest: GraphicsMediaRequest? = nil,
    mediaSelection: GraphicsMediaSelection = .virtual,
    outputDestinations: GraphicsOutputCatalog = .empty,
    outputType: Data? = nil,
    placement: GraphicsPagePlacement = .simplex,
    delivery: GraphicsPageDeliveryConfiguration = .virtual
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
    self.outputDeviceIdentifier = outputDeviceIdentifier
    self.outputDevice = outputDevice
    self.inputMedia = inputMedia
    self.mediaRequest = mediaRequest ?? GraphicsMediaRequest(
      attributes: GraphicsMediaAttributes(pageSize: pageSize)
    )
    self.mediaSelection = mediaSelection
    self.outputDestinations = outputDestinations
    self.outputType = outputType
    self.placement = placement
    self.delivery = delivery
  }
}
