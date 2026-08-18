/// A portable additive red, green, and blue color value.
public struct ColorRGB: Sendable, Hashable {
  /// The red component.
  public let red: Double
  /// The green component.
  public let green: Double
  /// The blue component.
  public let blue: Double

  /// Creates an RGB color without altering its components.
  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// Returns the color with every component limited to zero through one.
  public var clamped: Self {
    Self(red: red.clampedUnit, green: green.clampedUnit, blue: blue.clampedUnit)
  }
}

extension Double {
  var clampedUnit: Self { min(1, max(0, self)) }
}
