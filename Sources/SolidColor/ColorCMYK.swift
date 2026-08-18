/// A portable subtractive cyan, magenta, yellow, and black color value.
public struct ColorCMYK: Sendable, Hashable {
  /// The cyan component.
  public let cyan: Double
  /// The magenta component.
  public let magenta: Double
  /// The yellow component.
  public let yellow: Double
  /// The black component.
  public let black: Double

  /// Creates a CMYK color without altering its components.
  public init(cyan: Double, magenta: Double, yellow: Double, black: Double) {
    self.cyan = cyan
    self.magenta = magenta
    self.yellow = yellow
    self.black = black
  }

  /// Returns the nominal RGB conversion used by device-color fallbacks.
  public var rgb: ColorRGB {
    ColorRGB(
      red: 1 - min(1, cyan.clampedUnit + black.clampedUnit),
      green: 1 - min(1, magenta.clampedUnit + black.clampedUnit),
      blue: 1 - min(1, yellow.clampedUnit + black.clampedUnit)
    )
  }
}
