import Foundation

/// The available media sources and their selection priority.
public struct GraphicsMediaCatalog: Sendable, Hashable {
  /// Media sources keyed by their device position.
  public let sources: [Int: GraphicsMediaSource]
  /// Source positions in decreasing selection priority.
  public let priority: [Int]

  /// Creates a media catalog.
  public init(sources: [Int: GraphicsMediaSource] = [:], priority: [Int] = []) {
    self.sources = sources
    self.priority = priority
  }

  /// An empty catalog used by virtual devices.
  public static let empty = Self()
}
