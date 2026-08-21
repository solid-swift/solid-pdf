import Foundation

/// Transfer functions for the red, green, blue, and gray device primaries.
public struct GraphicsTransferFunctions: Sendable, Hashable {
  public let red: GraphicsComponentFunction
  public let green: GraphicsComponentFunction
  public let blue: GraphicsComponentFunction
  public let gray: GraphicsComponentFunction

  /// Creates a set of device transfer functions.
  public init(
    red: GraphicsComponentFunction = .identity,
    green: GraphicsComponentFunction = .identity,
    blue: GraphicsComponentFunction = .identity,
    gray: GraphicsComponentFunction = .identity
  ) {
    self.red = red
    self.green = green
    self.blue = blue
    self.gray = gray
  }

  /// Identity transfer for every process component.
  public static let identity = Self()
}
