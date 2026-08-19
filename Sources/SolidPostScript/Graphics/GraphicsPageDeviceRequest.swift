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

  /// Creates a page-device request.
  public init(
    pageSize: GraphicsSize,
    resolution: GraphicsSize,
    imagingBoundingBox: GraphicsRect?,
    numberOfCopies: Int?,
    colorants: GraphicsColorantConfiguration = .compositeRGB,
    trappingEnabled: Bool = false,
    trappingDetails: GraphicsTrappingDetails = GraphicsTrappingDetails()
  ) {
    self.pageSize = pageSize
    self.resolution = resolution
    self.imagingBoundingBox = imagingBoundingBox
    self.numberOfCopies = numberOfCopies
    self.colorants = colorants
    self.trappingEnabled = trappingEnabled
    self.trappingDetails = trappingDetails
  }
}
