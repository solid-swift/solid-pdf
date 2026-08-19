import Foundation
import SolidPostScript
import SolidRaster

/// Compiles portable PostScript device-rendering state for the native raster target.
public struct NativeGraphicsDeviceRenderingEngine: GraphicsDeviceRenderingEngine, Sendable {
  /// Creates a native device-rendering engine.
  public init() {}

  /// Creates one native render-scoped session.
  public func makeSession(
    for device: GraphicsDeviceDescriptor
  ) -> sending NativeGraphicsDeviceRenderingSession {
    NativeGraphicsDeviceRenderingSession()
  }
}

/// Render-scoped compiler for native raster transfer and halftone programs.
public final class NativeGraphicsDeviceRenderingSession: GraphicsDeviceRenderingSession {
  private var cachedState: GraphicsDeviceRenderingSnapshot?
  private var cachedDescriptor: GraphicsDeviceDescriptor?
  private var cachedProgram: RasterHalftoneProgram?

  /// Creates a native rendering session.
  public init() {}

  /// Compiles or reuses a raster device-rendering program.
  public func resolve(
    _ state: GraphicsDeviceRenderingSnapshot,
    for device: GraphicsDeviceDescriptor
  ) throws -> RasterHalftoneProgram {
    if cachedState == state, cachedDescriptor == device, let cachedProgram { return cachedProgram }
    do {
      let program = try RasterHalftoneProgram(
        redTransfer: state.effectiveTransferFunctions.red.samples,
        greenTransfer: state.effectiveTransferFunctions.green.samples,
        blueTransfer: state.effectiveTransferFunctions.blue.samples,
        grayTransfer: state.effectiveTransferFunctions.gray.samples,
        componentLevels: device.deviceRendering.quantization.levels,
        colorantLevels: device.deviceRendering.quantization.colorantLevels,
        defaultColorantLevels: device.deviceRendering.quantization.defaultColorantLevels,
        defaultScreen: try thresholdScreen(state.halftone),
        colorantScreens: try colorantScreens(state.halftone),
        colorantTransfers: Dictionary(uniqueKeysWithValues: device.colorants.availableColorants.map {
          ($0.name, state.transferFunction(for: $0.name).samples)
        })
      )
      cachedState = state
      cachedDescriptor = device
      cachedProgram = program
      return program
    } catch {
      throw SolidPostScript.Error.ioError
    }
  }

  private func thresholdScreen(_ halftone: GraphicsHalftone) throws -> RasterThresholdScreen? {
    switch halftone {
    case .continuous, .colorants:
      nil
    case .spot(let screen):
      try RasterThresholdScreen(
        width: screen.width,
        height: screen.height,
        maximumThreshold: UInt16.max,
        thresholds: screen.thresholds
      )
    case .threshold(let screen):
      try RasterThresholdScreen(
        width: screen.width,
        height: screen.height,
        maximumThreshold: screen.bitsPerSample == 8 ? 255 : UInt16.max,
        thresholds: screen.thresholds,
        secondaryWidth: screen.secondaryWidth,
        secondaryHeight: screen.secondaryHeight
      )
    }
  }

  private func colorantScreens(_ halftone: GraphicsHalftone) throws -> [String: RasterThresholdScreen] {
    guard case .colorants(let descriptions) = halftone else { return [:] }
    var result: [String: RasterThresholdScreen] = [:]
    for (name, description) in descriptions {
      if let screen = try thresholdScreen(description) { result[name] = screen }
    }
    return result
  }
}

private extension GraphicsDeviceQuantization {
  var levels: [Int]? {
    if case .discrete(let levels) = self { return levels }
    return nil
  }

  var colorantLevels: [String: Int] {
    if case .namedColorants(let levels, _) = self { return levels }
    return [:]
  }

  var defaultColorantLevels: Int? {
    if case .namedColorants(_, let levels) = self { return levels }
    return nil
  }
}
