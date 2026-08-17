import Foundation

/// A portable PostScript path stored in device coordinates.
public struct GraphicsPath: Sendable, Hashable {
  /// An element of a graphics path.
  public enum Element: Sendable, Hashable {
    /// Begins a new subpath.
    case move(to: GraphicsPoint)
    /// Adds a straight line segment.
    case line(to: GraphicsPoint)
    /// Adds a cubic Bezier segment.
    case curve(control1: GraphicsPoint, control2: GraphicsPoint, end: GraphicsPoint)
    /// Closes the current subpath.
    case close
  }

  /// The path elements in construction order.
  public private(set) var elements: [Element]

  /// Creates a path from elements.
  public init(elements: [Element] = []) {
    self.elements = elements
  }

  /// Whether the path has no elements.
  public var isEmpty: Bool { elements.isEmpty }

  mutating func append(_ element: Element) {
    elements.append(element)
  }

  mutating func removeAll() {
    elements.removeAll(keepingCapacity: true)
  }
}
