import Foundation

/// One numbered physical output destination.
public struct GraphicsOutputDestination: Sendable, Hashable {
  /// The device-defined destination position.
  public let position: Int
  /// The exact PostScript byte string identifying the destination type.
  public let type: Data
  /// Whether every destination attribute must be requested explicitly.
  public let matchesAllAttributes: Bool

  /// Creates an output destination.
  public init(position: Int, type: Data, matchesAllAttributes: Bool = false) {
    self.position = position
    self.type = type
    self.matchesAllAttributes = matchesAllAttributes
  }
}
