import Foundation

/// Limits and behaviors supported by one page-device provider.
public struct GraphicsPageDeviceCapabilities: Sendable, Hashable {
  /// Whether page size and resolution can change during a render.
  public let mode: GraphicsPageDeviceMode
  /// The maximum pixel width of a negotiated page.
  public let maximumPixelWidth: Int
  /// The maximum pixel height of a negotiated page.
  public let maximumPixelHeight: Int
  /// The maximum number of RGBA8 bytes in one page.
  public let maximumSurfaceBytes: Int
  /// The process, named-colorant, separation, and overprint capabilities.
  public let colorants: GraphicsColorantCapabilities
  /// The trapping implementations accepted by the provider.
  public let trapping: GraphicsTrappingCapabilities

  /// Creates page-device capabilities.
  public init(
    mode: GraphicsPageDeviceMode,
    maximumPixelWidth: Int = 32_768,
    maximumPixelHeight: Int = 32_768,
    maximumSurfaceBytes: Int = 512 * 1_024 * 1_024,
    colorants: GraphicsColorantCapabilities = .compositeRGB,
    trapping: GraphicsTrappingCapabilities = .unsupported
  ) {
    self.mode = mode
    self.maximumPixelWidth = maximumPixelWidth
    self.maximumPixelHeight = maximumPixelHeight
    self.maximumSurfaceBytes = maximumSurfaceBytes
    self.colorants = colorants
    self.trapping = trapping
  }
}
