import Foundation

/// The available output destinations and their selection priority.
public struct GraphicsOutputCatalog: Sendable, Hashable {
  /// Destinations keyed by their device position.
  public let destinations: [Int: GraphicsOutputDestination]
  /// Destination positions in decreasing selection priority.
  public let priority: [Int]

  /// Creates an output catalog.
  public init(destinations: [Int: GraphicsOutputDestination] = [:], priority: [Int] = []) {
    self.destinations = destinations
    self.priority = priority
  }

  /// An empty catalog used by devices without destination selection.
  public static let empty = Self()
}
