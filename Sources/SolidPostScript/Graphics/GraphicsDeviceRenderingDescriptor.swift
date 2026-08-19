import Foundation

/// Device capabilities and defaults for transfer and halftone realization.
public struct GraphicsDeviceRenderingDescriptor: Sendable, Hashable {
  public let quantization: GraphicsDeviceQuantization
  public let samplePrecision: Int
  public let defaultState: GraphicsDeviceRenderingSnapshot

  /// Creates a rendering descriptor.
  public init(
    quantization: GraphicsDeviceQuantization = .continuousTone,
    samplePrecision: Int = 12,
    defaultState: GraphicsDeviceRenderingSnapshot = .continuousTone
  ) {
    self.quantization = quantization
    self.samplePrecision = min(16, max(8, samplePrecision))
    self.defaultState = defaultState
  }

  /// The default identity continuous-tone device.
  public static let continuousTone = Self()
}
