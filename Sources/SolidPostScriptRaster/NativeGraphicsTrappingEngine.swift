import Foundation
import SolidPostScript
import SolidRaster

/// The native Type 1001 trapping engine used by separated raster output.
public struct NativeGraphicsTrappingEngine: GraphicsTrappingEngine, Sendable {
  /// Creates a native trapping engine.
  public init() {}

  /// Creates a render-scoped trapping session.
  public func makeSession(
    for device: GraphicsDeviceDescriptor
  ) -> sending NativeGraphicsTrappingSession {
    NativeGraphicsTrappingSession()
  }
}

/// Compiles portable trapping parameters into separated-raster programs.
public final class NativeGraphicsTrappingSession: GraphicsTrappingSession, Sendable {
  /// Creates a native trapping session.
  public init() {}

  /// Resolves Type 1001 state for a raster page.
  public func resolve(
    _ state: GraphicsTrappingSnapshot,
    for device: GraphicsDeviceDescriptor
  ) throws -> RasterTrappingProgram {
    guard state.enabled, state.parameters.enabled else { return .disabled }
    guard state.details.type == 1001,
      device.trapping.capabilities.supportedTypes.contains(1001)
    else { throw SolidPostScript.Error.configurationError }
    let scale = max(device.horizontalResolution, device.verticalResolution) / 72
    return RasterTrappingProgram(
      enabled: true,
      width: state.parameters.trapWidth * scale,
      stepLimit: state.parameters.stepLimit,
      colorScaling: state.parameters.trapColorScaling,
      blackDensityLimit: state.parameters.blackDensityLimit,
      blackColorLimit: state.parameters.blackColorLimit,
      blackWidth: state.parameters.blackWidth,
      slidingLimit: state.parameters.slidingTrapLimit,
      trapsImagesToObjects: state.parameters.imageToObjectTrapping,
      trapsInsideImages: state.parameters.imageInternalTrapping
    )
  }
}
