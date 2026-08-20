import Foundation

/// Static capabilities and media catalogs for one selectable output device.
public struct GraphicsOutputDeviceProfile: Sendable, Hashable {
  /// The stable physical output-device identity.
  public let identifier: GraphicsOutputDeviceIdentifier
  /// The resource name and `OutputDevice` parameter value.
  public let resourceName: String
  /// The page-device name used by color-rendering selection.
  public let pageDeviceName: String
  /// The input-media catalog.
  public let inputMedia: GraphicsMediaCatalog
  /// The output-destination catalog.
  public let outputDestinations: GraphicsOutputCatalog
  /// The supported physical behaviors.
  public let physicalCapabilities: GraphicsPhysicalPageDeviceCapabilities

  /// Creates an output-device profile.
  public init(
    identifier: GraphicsOutputDeviceIdentifier = .init(),
    resourceName: String,
    pageDeviceName: String? = nil,
    inputMedia: GraphicsMediaCatalog = .empty,
    outputDestinations: GraphicsOutputCatalog = .empty,
    physicalCapabilities: GraphicsPhysicalPageDeviceCapabilities = .virtual
  ) {
    self.identifier = identifier
    self.resourceName = resourceName
    self.pageDeviceName = pageDeviceName ?? resourceName
    self.inputMedia = inputMedia
    self.outputDestinations = outputDestinations
    self.physicalCapabilities = physicalCapabilities
  }
}
