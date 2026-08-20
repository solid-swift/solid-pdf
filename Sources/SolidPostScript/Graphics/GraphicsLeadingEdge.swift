import Foundation

/// The edge of portrait-oriented media that enters an imaging mechanism first.
public enum GraphicsLeadingEdge: Int, Sendable, Hashable, CaseIterable {
  /// The top short edge.
  case top = 0
  /// The right long edge.
  case right = 1
  /// The bottom short edge.
  case bottom = 2
  /// The left long edge.
  case left = 3
}
