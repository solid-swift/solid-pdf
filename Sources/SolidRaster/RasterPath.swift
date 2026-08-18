import Foundation

/// An immutable vector path with copy-on-write element storage.
public struct RasterPath: Sendable, Hashable {
  /// One path construction element.
  public enum Element: Sendable, Hashable {
    /// Begins a subpath.
    case move(to: RasterPoint)
    /// Adds a line.
    case line(to: RasterPoint)
    /// Adds a cubic Bezier curve.
    case cubic(control1: RasterPoint, control2: RasterPoint, end: RasterPoint)
    /// Closes the current subpath.
    case close
  }

  /// A uniquely owned, noncopyable path builder.
  public struct Builder: ~Copyable {
    private var elements: ContiguousArray<Element>
    private let limit: Int

    /// Creates an empty builder.
    public init(limit: Int = RasterLimits.default.maximumPathElements) {
      elements = []
      self.limit = limit
    }

    /// Begins a subpath.
    public mutating func move(to point: RasterPoint) throws(RasterError) {
      try append(.move(to: point))
    }

    /// Adds a line.
    public mutating func line(to point: RasterPoint) throws(RasterError) {
      try append(.line(to: point))
    }

    /// Adds a cubic Bezier curve.
    public mutating func cubic(
      control1: RasterPoint,
      control2: RasterPoint,
      end: RasterPoint
    ) throws(RasterError) {
      try append(.cubic(control1: control1, control2: control2, end: end))
    }

    /// Closes the current subpath.
    public mutating func close() throws(RasterError) {
      try append(.close)
    }

    /// Consumes the builder and returns its immutable path.
    public consuming func finish() -> RasterPath {
      RasterPath(elements: Array(elements))
    }

    private mutating func append(_ element: Element) throws(RasterError) {
      guard elements.count < limit else { throw .limitExceeded }
      elements.append(element)
    }
  }

  /// Elements in construction order.
  public let elements: [Element]

  /// Creates a path.
  public init(elements: [Element] = []) {
    self.elements = elements
  }

  /// Whether the path has no elements.
  public var isEmpty: Bool { elements.isEmpty }

  /// Returns a transformed path.
  public func transformed(by transform: RasterAffineTransform) -> Self {
    Self(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: transform.transform(point))
      case .line(let point): .line(to: transform.transform(point))
      case .cubic(let control1, let control2, let end):
        .cubic(
          control1: transform.transform(control1),
          control2: transform.transform(control2),
          end: transform.transform(end)
        )
      case .close: .close
      }
    })
  }
}
