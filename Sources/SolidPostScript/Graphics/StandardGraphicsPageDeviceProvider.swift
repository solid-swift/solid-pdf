import Foundation

/// The built-in virtual page-device provider used by standard graphics targets.
public struct StandardGraphicsPageDeviceProvider: GraphicsPageDeviceProvider, Sendable {
  /// The negotiation mode used for new sessions.
  public let mode: GraphicsPageDeviceMode
  /// The maximum pixel width of a page.
  public let maximumPixelWidth: Int
  /// The maximum pixel height of a page.
  public let maximumPixelHeight: Int
  /// The maximum number of RGBA8 bytes in one page.
  public let maximumSurfaceBytes: Int
  /// The page-device name reported to PostScript.
  public let name: String

  /// Creates a standard page-device provider.
  public init(
    mode: GraphicsPageDeviceMode = .adaptive,
    maximumPixelWidth: Int = 32_768,
    maximumPixelHeight: Int = 32_768,
    maximumSurfaceBytes: Int = 512 * 1_024 * 1_024,
    name: String = "SolidVirtualPageDevice"
  ) {
    self.mode = mode
    self.maximumPixelWidth = maximumPixelWidth
    self.maximumPixelHeight = maximumPixelHeight
    self.maximumSurfaceBytes = maximumSurfaceBytes
    self.name = name
  }

  /// Creates a render-scoped standard session.
  public func makeSession(
    for descriptor: GraphicsDeviceDescriptor
  ) throws -> sending StandardGraphicsPageDeviceSession {
    try StandardGraphicsPageDeviceSession(
      descriptor: descriptor,
      capabilities: GraphicsPageDeviceCapabilities(
        mode: mode,
        maximumPixelWidth: maximumPixelWidth,
        maximumPixelHeight: maximumPixelHeight,
        maximumSurfaceBytes: maximumSurfaceBytes
      ),
      name: name
    )
  }
}
