import Foundation

/// Trapping support and default state supplied by a graphics device.
public struct GraphicsTrappingDescriptor: Sendable, Hashable {
  /// The device's supported trapping behavior.
  public let capabilities: GraphicsTrappingCapabilities
  /// Initial Type 1001 colorant details.
  public let defaultDetails: GraphicsTrappingDetails
  /// Initial trapping parameters.
  public let defaultParameters: GraphicsTrappingParameters

  /// Creates a trapping descriptor.
  public init(
    capabilities: GraphicsTrappingCapabilities = .unsupported,
    defaultDetails: GraphicsTrappingDetails = GraphicsTrappingDetails(),
    defaultParameters: GraphicsTrappingParameters = GraphicsTrappingParameters()
  ) {
    self.capabilities = capabilities
    self.defaultDetails = defaultDetails
    self.defaultParameters = defaultParameters
  }

  /// A device without trapping support.
  public static let unsupported = Self()
  /// A semantic Type 1001 device.
  public static let semanticType1001 = Self(capabilities: .semanticType1001)
  /// A native separated-raster Type 1001 device.
  public static let rasterType1001 = Self(capabilities: .rasterType1001)
}
