import Foundation

/// Immutable device-dependent rendering controls captured with graphics state.
public struct GraphicsDeviceRenderingSnapshot: Sendable, Hashable {
  public let transferFunctions: GraphicsTransferFunctions
  public let blackGeneration: GraphicsComponentFunction
  public let undercolorRemoval: GraphicsComponentFunction
  public let halftone: GraphicsHalftone
  /// The absolute device-space phase applied to halftone screens.
  public let halftonePhase: GraphicsPoint

  /// Creates a device-rendering snapshot.
  public init(
    transferFunctions: GraphicsTransferFunctions = .identity,
    blackGeneration: GraphicsComponentFunction = .zero,
    undercolorRemoval: GraphicsComponentFunction = .zero,
    halftone: GraphicsHalftone = .default,
    halftonePhase: GraphicsPoint = GraphicsPoint(x: 0, y: 0)
  ) {
    self.transferFunctions = transferFunctions
    self.blackGeneration = blackGeneration
    self.undercolorRemoval = undercolorRemoval
    self.halftone = halftone
    self.halftonePhase = halftonePhase
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

  /// Returns the effective transfer function for a process or named colorant.
  public func transferFunction(for colorant: String) -> GraphicsComponentFunction {
    if let function = halftone.transferFunction(for: colorant) { return function }
    return switch colorant {
    case "Red", "Cyan": transferFunctions.red
    case "Green", "Magenta": transferFunctions.green
    case "Blue", "Yellow": transferFunctions.blue
    case "Gray", "Black": transferFunctions.gray
    default: transferFunctions.gray
    }
  }
}

extension GraphicsHalftone {
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
