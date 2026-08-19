import SolidColor

/// Portable process-color capabilities advertised by a graphics target.
public struct GraphicsColorDeviceDescriptor: Sendable, Hashable {
  /// The process-color model produced by the target.
  public let processModel: ColorDestinationProfile.Model
  /// The portable destination profile used by the reference engine.
  public let destinationProfile: ColorDestinationProfile
  /// Named colorants the device can preserve without using an alternative space.
  public let supportedColorants: Set<String>
  /// Installation-defined resource name used for color-rendering lookup.
  public let deviceName: String

  /// Creates a color-device descriptor.
  public init(
    processModel: ColorDestinationProfile.Model = .rgb,
    destinationProfile: ColorDestinationProfile = .sRGB,
    supportedColorants: Set<String> = [],
    deviceName: String = "Default"
  ) {
    self.processModel = processModel
    self.destinationProfile = destinationProfile
    self.supportedColorants = supportedColorants
    self.deviceName = deviceName
  }

  /// The default sRGB bitmap device.
  public static let sRGB = Self()
}
