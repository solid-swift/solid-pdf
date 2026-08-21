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

  mutating func append(_ element: Element) throws {
    guard elements.count < LanguageLimits.maximumPathElements else { throw Error.limitCheck }
    elements.append(element)
  }

  mutating func removeAll() {
    elements.removeAll(keepingCapacity: true)
  }

  var currentPoint: GraphicsPoint? {
    guard let last = elements.last else { return nil }
    switch last {
    case .move(let point), .line(let point), .curve(_, _, let point):
      return point
    case .close:
      return currentSubpathStart
    }
  }

  var currentSubpathStart: GraphicsPoint? {
    for element in elements.reversed() {
      if case .move(let point) = element {
        return point
      }
    }
    return nil
  }

  var currentSubpathIsClosed: Bool {
    guard case .close? = elements.last else { return false }
    return true
  }

  var boundingPoints: [GraphicsPoint] {
    var points: [GraphicsPoint] = []
    for (index, element) in elements.enumerated() {
      if index == elements.count - 1, case .move = element, elements.count > 1 { continue }
      points.append(contentsOf: element.points)
    }
    return points
  }

  func transformed(by matrix: GraphicsMatrix) -> Self {
    Self(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: matrix.transform(point))
      case .line(let point): .line(to: matrix.transform(point))
      case .curve(let control1, let control2, let end):
        .curve(
          control1: matrix.transform(control1),
          control2: matrix.transform(control2),
          end: matrix.transform(end)
        )
      case .close: .close
      }
    })
  }

  func reversedPath() throws -> Self {
    struct Segment {
      let start: GraphicsPoint
      let element: Element
      let end: GraphicsPoint
    }
    var result = GraphicsPath()
    var subpathStart: GraphicsPoint?
    var current: GraphicsPoint?
    var segments: [Segment] = []
    var closed = false

    func appendSubpath() throws {
      guard let start = subpathStart else { return }
      guard let end = segments.last?.end else {
        try result.append(.move(to: start))
        return
      }
      try result.append(.move(to: closed ? start : end))
      for segment in segments.reversed() {
        switch segment.element {
        case .line:
          try result.append(.line(to: segment.start))
        case .curve(let control1, let control2, _):
          try result.append(.curve(control1: control2, control2: control1, end: segment.start))
        case .move, .close:
          break
        }
      }
      if closed { try result.append(.close) }
    }

    for element in elements {
      switch element {
      case .move(let point):
        try appendSubpath()
        subpathStart = point
        current = point
        segments.removeAll(keepingCapacity: true)
        closed = false
      case .line(let point):
        guard let segmentStart = current else { continue }
        segments.append(Segment(start: segmentStart, element: element, end: point))
        current = point
      case .curve(_, _, let point):
        guard let segmentStart = current else { continue }
        segments.append(Segment(start: segmentStart, element: element, end: point))
        current = point
      case .close:
        if let current, let subpathStart, current != subpathStart {
          segments.append(Segment(start: current, element: .line(to: subpathStart), end: subpathStart))
        }
        closed = true
        current = subpathStart
      }
    }
    try appendSubpath()
    return result
  }
}

extension GraphicsPath.Element {
  var points: [GraphicsPoint] {
    switch self {
    case .move(let point), .line(let point): [point]
    case .curve(let control1, let control2, let end): [control1, control2, end]
    case .close: []
    }
  }
}
