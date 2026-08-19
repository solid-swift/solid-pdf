import Foundation
import SolidPostScript

/// A page-device provider that advertises native raster separation output.
public struct RasterSeparationPageDeviceProvider: GraphicsPageDeviceProvider, Sendable {
  /// The negotiation mode used for new render sessions.
  public let mode: GraphicsPageDeviceMode

  /// Creates a raster separation provider.
  public init(mode: GraphicsPageDeviceMode = .adaptive) {
    self.mode = mode
  }

  /// Creates a render-scoped page-device session with dynamic named colorants.
  public func makeSession(
    for descriptor: GraphicsDeviceDescriptor
  ) throws -> sending StandardGraphicsPageDeviceSession {
    var processModels = Set(GraphicsProcessColorModel.allCases.filter { $0 != .deviceN })
    if descriptor.colorants.hasUsableDeviceNLookup { processModels.insert(.deviceN) }
    return try StandardGraphicsPageDeviceProvider(
      mode: mode,
      name: "SolidRasterSeparationDevice",
      colorantCapabilities: GraphicsColorantCapabilities(
        supportedProcessModels: processModels,
        supportsCompositeOutput: true,
        supportsSeparationOutput: true,
        supportsOverprint: true,
        acceptsDynamicColorants: true,
        maximumSeparations: 250
      )
    ).makeSession(for: descriptor)
  }
}
