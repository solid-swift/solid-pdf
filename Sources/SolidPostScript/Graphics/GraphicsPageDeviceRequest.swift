import Foundation

/// A fully merged request presented to a page-device provider for negotiation.
public struct GraphicsPageDeviceRequest: Sendable, Hashable {
  /// The requested medium size in default-user-space points.
  public let pageSize: GraphicsSize
  /// The requested horizontal and vertical resolution in pixels per inch.
  public let resolution: GraphicsSize
  /// The optional asserted imaging bounds in default user space.
  public let imagingBoundingBox: GraphicsRect?
  /// The requested copy count, or `nil` to use `#copies`.
  public let numberOfCopies: Int?
  /// The requested process and named-colorant configuration.
  public let colorants: GraphicsColorantConfiguration
  /// Whether the requested page device should perform in-RIP trapping.
  public let trappingEnabled: Bool
  /// The requested type-specific trapping details.
  public let trappingDetails: GraphicsTrappingDetails
  /// Whether Device color spaces should be remapped through Default ColorSpace resources.
  public let usesCIEColor: Bool
  /// The requested stable output-device resource name.
  public let outputDevice: String?
  /// The current input-media catalog after cumulative merging.
  public let inputMedia: GraphicsMediaCatalog
  /// The normalized physical media request.
  public let mediaRequest: GraphicsMediaRequest
  /// The current output-destination catalog after cumulative merging.
  public let outputDestinations: GraphicsOutputCatalog
  /// The requested destination type, or `nil` for no preference.
  public let outputType: Data?
  /// The requested physical placement.
  public let placement: GraphicsPagePlacement
  /// The requested delivery and roll-media behavior.
  public let delivery: GraphicsPageDeliveryConfiguration

  /// Creates a page-device request.
  public init(
    pageSize: GraphicsSize,
    resolution: GraphicsSize,
    imagingBoundingBox: GraphicsRect?,
    numberOfCopies: Int?,
    colorants: GraphicsColorantConfiguration = .compositeRGB,
    trappingEnabled: Bool = false,
    trappingDetails: GraphicsTrappingDetails = GraphicsTrappingDetails(),
    usesCIEColor: Bool = false,
    outputDevice: String? = nil,
    inputMedia: GraphicsMediaCatalog = .empty,
    mediaRequest: GraphicsMediaRequest? = nil,
    outputDestinations: GraphicsOutputCatalog = .empty,
    outputType: Data? = nil,
    placement: GraphicsPagePlacement = .simplex,
    delivery: GraphicsPageDeliveryConfiguration = .virtual
  ) {
    self.pageSize = pageSize
    self.resolution = resolution
    self.imagingBoundingBox = imagingBoundingBox
    self.numberOfCopies = numberOfCopies
    self.colorants = colorants
    self.trappingEnabled = trappingEnabled
    self.trappingDetails = trappingDetails
    self.usesCIEColor = usesCIEColor
    self.outputDevice = outputDevice
    self.inputMedia = inputMedia
    self.mediaRequest = mediaRequest ?? GraphicsMediaRequest(
      attributes: GraphicsMediaAttributes(pageSize: pageSize)
    )
    self.outputDestinations = outputDestinations
    self.outputType = outputType
    self.placement = placement
    self.delivery = delivery
  }
}
