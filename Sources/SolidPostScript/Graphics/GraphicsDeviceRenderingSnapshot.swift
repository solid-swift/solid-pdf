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
    halftone: GraphicsHalftone = .default
  ) {
    self.transferFunctions = transferFunctions
    self.blackGeneration = blackGeneration
    self.undercolorRemoval = undercolorRemoval
    self.halftone = halftone
  }

  /// Identity continuous-tone rendering controls.
  public static let continuousTone = Self()

  /// The graphics-state transfers after applying any halftone-dictionary overrides.
  public var effectiveTransferFunctions: GraphicsTransferFunctions {
    GraphicsTransferFunctions(
      red: halftone.transferFunction(for: "Red") ?? transferFunctions.red,
      green: halftone.transferFunction(for: "Green") ?? transferFunctions.green,
      blue: halftone.transferFunction(for: "Blue") ?? transferFunctions.blue,
      gray: halftone.transferFunction(for: "Gray") ?? transferFunctions.gray
    )
  }
}

private extension GraphicsHalftone {
  func transferFunction(for colorant: String) -> GraphicsComponentFunction? {
    switch self {
    case .continuous:
      nil
    case .spot(let screen):
      screen.transferFunction
    case .threshold(let screen):
      screen.transferFunction
    case .colorants(let screens):
      (screens[colorant] ?? screens["Default"])?.transferFunction(for: colorant)
    }
  }
}
