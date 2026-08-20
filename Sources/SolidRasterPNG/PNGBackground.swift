/// An 8-bit background used when flattening alpha.
public struct PNGBackground: Sendable, Hashable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  /// Creates an RGB background.
  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public static let white = Self(red: 255, green: 255, blue: 255)
}
