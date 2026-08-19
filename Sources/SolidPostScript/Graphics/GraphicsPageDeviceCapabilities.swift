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

  /// Creates page-device capabilities.
  public init(
    mode: GraphicsPageDeviceMode,
    maximumPixelWidth: Int = 32_768,
    maximumPixelHeight: Int = 32_768,
    maximumSurfaceBytes: Int = 512 * 1_024 * 1_024
  ) {
    self.mode = mode
    self.maximumPixelWidth = maximumPixelWidth
    self.maximumPixelHeight = maximumPixelHeight
    self.maximumSurfaceBytes = maximumSurfaceBytes
  }
}
