import Foundation

/// Immutable device-dependent rendering controls captured with graphics state.
public struct GraphicsDeviceRenderingSnapshot: Sendable, Hashable {
  public let transferFunctions: GraphicsTransferFunctions
  public let blackGeneration: GraphicsComponentFunction
  public let undercolorRemoval: GraphicsComponentFunction
  public let halftone: GraphicsHalftone

  /// Creates a device-rendering snapshot.
  public init(
    transferFunctions: GraphicsTransferFunctions = .identity,
    blackGeneration: GraphicsComponentFunction = .zero,
    undercolorRemoval: GraphicsComponentFunction = .zero,
    halftone: GraphicsHalftone = .continuous
  ) {
    self.transferFunctions = transferFunctions
    self.blackGeneration = blackGeneration
    self.undercolorRemoval = undercolorRemoval
    self.halftone = halftone
  }

  /// Identity continuous-tone rendering controls.
  public static let continuousTone = Self()
}
