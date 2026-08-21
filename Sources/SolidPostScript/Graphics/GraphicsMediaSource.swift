import Foundation

/// One numbered source of physical media.
public struct GraphicsMediaSource: Sendable, Hashable {
  /// The device-defined source position.
  public let position: Int
  /// The currently available media, or `nil` when the source is unavailable.
  public let attributes: GraphicsMediaAttributes?
  /// Whether every non-null source attribute must be requested explicitly.
  public let matchesAllAttributes: Bool
  /// Whether this source represents a manual feeder.
  public let isManual: Bool

  /// Creates a media source.
  public init(
    position: Int,
    attributes: GraphicsMediaAttributes?,
    matchesAllAttributes: Bool = false,
    isManual: Bool = false
  ) {
    self.position = position
    self.attributes = attributes
    self.matchesAllAttributes = matchesAllAttributes
    self.isManual = isManual
  }
}
