import Foundation

/// A fixed 26.6 trapezoid used by a canonical vector region.
package struct RasterTrapezoid: Sendable, Hashable {
  package let minimumY: Int64
  package let maximumY: Int64
  package let leftAtMinimumY: Int64
  package let leftAtMaximumY: Int64
  package let rightAtMinimumY: Int64
  package let rightAtMaximumY: Int64
}

/// A deterministic vector region represented by non-overlapping 26.6 trapezoids.
package struct RasterRegion: Sendable, Hashable {
  package let trapezoids: [RasterTrapezoid]

  package init(trapezoids: [RasterTrapezoid] = []) {
    self.trapezoids = trapezoids
  }

  package var isEmpty: Bool { trapezoids.isEmpty }

  package static func rectangle(_ rect: RasterRect) throws(RasterError) -> Self {
    guard rect.width.isFinite, rect.height.isFinite, rect.width >= 0, rect.height >= 0 else {
      throw .invalidGeometry
    }
    guard rect.width > 0, rect.height > 0 else { return Self() }
    let minimumX = try FreeTypeFixedMath.outlineCoordinate(rect.x)
    let maximumX = try FreeTypeFixedMath.outlineCoordinate(rect.maxX)
    let minimumY = try FreeTypeFixedMath.outlineCoordinate(rect.y)
    let maximumY = try FreeTypeFixedMath.outlineCoordinate(rect.maxY)
    return Self(trapezoids: [RasterTrapezoid(
      minimumY: minimumY,
      maximumY: maximumY,
      leftAtMinimumY: minimumX,
      leftAtMaximumY: minimumX,
      rightAtMinimumY: maximumX,
      rightAtMaximumY: maximumX
    )])
  }

  package static func path(
    _ path: RasterPath,
    rule: RasterFillRule,
    flatness: Double,
    limits: RasterLimits = .default
  ) throws(RasterError) -> Self {
    let flattened = try PathFlattener.flatten(path, flatness: flatness)
    var edges: [Edge] = []
    edges.reserveCapacity(path.elements.count)
    for subpath in flattened.subpaths {
      guard subpath.points.count > 1 else { continue }
      for index in 1..<subpath.points.count {
        try appendEdge(from: subpath.points[index - 1], to: subpath.points[index], into: &edges)
      }
      if subpath.isClosed, let first = subpath.points.first, let last = subpath.points.last {
        try appendEdge(from: last, to: first, into: &edges)
      }
    }
    guard !edges.isEmpty else { return Self() }

    var boundaries = edges.flatMap { [$0.minimumY, $0.maximumY] }
    for firstIndex in edges.indices {
      for secondIndex in edges.indices where secondIndex > firstIndex {
        if let crossing = edges[firstIndex].crossingY(with: edges[secondIndex]) {
          boundaries.append(crossing)
        }
      }
    }
    boundaries.sort()
    boundaries = boundaries.reduce(into: []) { result, value in
      if result.last != value { result.append(value) }
    }

    var output: [RasterTrapezoid] = []
    output.reserveCapacity(min(limits.maximumPathElements, edges.count * 2))
    for index in 1..<boundaries.count {
      let minimumY = boundaries[index - 1]
      let maximumY = boundaries[index]
      guard maximumY > minimumY else { continue }
      let middleY = minimumY + (maximumY - minimumY) / 2
      var crossings = edges.compactMap { edge -> Crossing? in
        guard edge.contains(y: middleY) else { return nil }
        return Crossing(edge: edge, x: edge.x(at: middleY))
      }
      crossings.sort { lhs, rhs in
        lhs.x == rhs.x ? lhs.edge.winding < rhs.edge.winding : lhs.x < rhs.x
      }
      var intervalStart: Edge?
      var winding = 0
      for crossing in crossings {
        let wasInside = rule == .evenOdd ? winding.isMultiple(of: 2) == false : winding != 0
        winding += rule == .evenOdd ? 1 : crossing.edge.winding
        let isInside = rule == .evenOdd ? winding.isMultiple(of: 2) == false : winding != 0
        if !wasInside, isInside {
          intervalStart = crossing.edge
        } else if wasInside, !isInside, let left = intervalStart {
          let right = crossing.edge
          let trapezoid = try makeTrapezoid(
            minimumY: minimumY,
            maximumY: maximumY,
            left: left,
            right: right
          )
          if trapezoid.rightAtMinimumY > trapezoid.leftAtMinimumY
            || trapezoid.rightAtMaximumY > trapezoid.leftAtMaximumY
          {
            guard output.count < limits.maximumPathElements else { throw .limitExceeded }
            output.append(trapezoid)
          }
          intervalStart = nil
        }
      }
    }
    return Self(trapezoids: output)
  }

  package func intersecting(
    _ other: Self,
    limits: RasterLimits = .default
  ) throws(RasterError) -> Self {
    var output: [RasterTrapezoid] = []
    for lhs in trapezoids {
      for rhs in other.trapezoids {
        let minimumY = max(lhs.minimumY, rhs.minimumY)
        let maximumY = min(lhs.maximumY, rhs.maximumY)
        guard maximumY > minimumY else { continue }
        var boundaries = [minimumY, maximumY]
        Self.appendCrossing(
          firstStart: lhs.left(at: minimumY), firstEnd: lhs.left(at: maximumY),
          secondStart: rhs.left(at: minimumY), secondEnd: rhs.left(at: maximumY),
          minimumY: minimumY, maximumY: maximumY, into: &boundaries
        )
        Self.appendCrossing(
          firstStart: lhs.right(at: minimumY), firstEnd: lhs.right(at: maximumY),
          secondStart: rhs.right(at: minimumY), secondEnd: rhs.right(at: maximumY),
          minimumY: minimumY, maximumY: maximumY, into: &boundaries
        )
        boundaries.sort()
        for index in 1..<boundaries.count {
          let lower = boundaries[index - 1]
          let upper = boundaries[index]
          guard upper > lower else { continue }
          let leftLower = max(lhs.left(at: lower), rhs.left(at: lower))
          let leftUpper = max(lhs.left(at: upper), rhs.left(at: upper))
          let rightLower = min(lhs.right(at: lower), rhs.right(at: lower))
          let rightUpper = min(lhs.right(at: upper), rhs.right(at: upper))
          guard rightLower > leftLower || rightUpper > leftUpper else { continue }
          guard output.count < limits.maximumPathElements else { throw .limitExceeded }
          output.append(RasterTrapezoid(
            minimumY: lower,
            maximumY: upper,
            leftAtMinimumY: leftLower,
            leftAtMaximumY: leftUpper,
            rightAtMinimumY: rightLower,
            rightAtMaximumY: rightUpper
          ))
        }
      }
    }
    return Self(trapezoids: output)
  }

  package func path(limit: Int = RasterLimits.default.maximumPathElements) throws(RasterError) -> RasterPath {
    var builder = RasterPath.Builder(limit: limit)
    for trapezoid in trapezoids {
      try builder.move(to: trapezoid.point(x: trapezoid.leftAtMinimumY, y: trapezoid.minimumY))
      try builder.line(to: trapezoid.point(x: trapezoid.rightAtMinimumY, y: trapezoid.minimumY))
      try builder.line(to: trapezoid.point(x: trapezoid.rightAtMaximumY, y: trapezoid.maximumY))
      try builder.line(to: trapezoid.point(x: trapezoid.leftAtMaximumY, y: trapezoid.maximumY))
      try builder.close()
    }
    return builder.finish()
  }

  package func intersects(_ other: Self) -> Bool {
    for lhs in trapezoids {
      for rhs in other.trapezoids {
        let minimumY = max(lhs.minimumY, rhs.minimumY)
        let maximumY = min(lhs.maximumY, rhs.maximumY)
        guard maximumY > minimumY else { continue }
        let middle = minimumY + (maximumY - minimumY) / 2
        if min(lhs.right(at: middle), rhs.right(at: middle))
          > max(lhs.left(at: middle), rhs.left(at: middle))
        {
          return true
        }
      }
    }
    return false
  }
}

extension RasterRegion {
  private struct Crossing {
    let edge: Edge
    let x: Double
  }

  private struct Edge {
    let start: RasterPoint
    let end: RasterPoint
    let minimumY: Double
    let maximumY: Double
    let winding: Int

    func contains(y: Double) -> Bool { y >= minimumY && y < maximumY }

    func x(at y: Double) -> Double {
      start.x + (end.x - start.x) * ((y - start.y) / (end.y - start.y))
    }

    func crossingY(with other: Self) -> Double? {
      let lower = max(minimumY, other.minimumY)
      let upper = min(maximumY, other.maximumY)
      guard upper > lower else { return nil }
      let firstDifference = x(at: lower) - other.x(at: lower)
      let lastDifference = x(at: upper) - other.x(at: upper)
      guard firstDifference != 0, lastDifference != 0,
        (firstDifference < 0) != (lastDifference < 0)
      else { return nil }
      let ratio = abs(firstDifference) / (abs(firstDifference) + abs(lastDifference))
      return lower + (upper - lower) * ratio
    }
  }

  private static func appendEdge(
    from start: RasterPoint,
    to end: RasterPoint,
    into edges: inout [Edge]
  ) throws(RasterError) {
    guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
      throw .invalidGeometry
    }
    guard start.y != end.y else { return }
    edges.append(Edge(
      start: start,
      end: end,
      minimumY: min(start.y, end.y),
      maximumY: max(start.y, end.y),
      winding: end.y > start.y ? 1 : -1
    ))
  }

  private static func makeTrapezoid(
    minimumY: Double,
    maximumY: Double,
    left: Edge,
    right: Edge
  ) throws(RasterError) -> RasterTrapezoid {
    RasterTrapezoid(
      minimumY: try FreeTypeFixedMath.outlineCoordinate(minimumY),
      maximumY: try FreeTypeFixedMath.outlineCoordinate(maximumY),
      leftAtMinimumY: try FreeTypeFixedMath.outlineCoordinate(left.x(at: minimumY)),
      leftAtMaximumY: try FreeTypeFixedMath.outlineCoordinate(left.x(at: maximumY)),
      rightAtMinimumY: try FreeTypeFixedMath.outlineCoordinate(right.x(at: minimumY)),
      rightAtMaximumY: try FreeTypeFixedMath.outlineCoordinate(right.x(at: maximumY))
    )
  }

  private static func appendCrossing(
    firstStart: Int64,
    firstEnd: Int64,
    secondStart: Int64,
    secondEnd: Int64,
    minimumY: Int64,
    maximumY: Int64,
    into boundaries: inout [Int64]
  ) {
    let startDifference = firstStart - secondStart
    let endDifference = firstEnd - secondEnd
    guard startDifference != 0, endDifference != 0,
      (startDifference < 0) != (endDifference < 0)
    else { return }
    let denominator = Double(abs(startDifference)) + Double(abs(endDifference))
    let ratio = Double(abs(startDifference)) / denominator
    let crossing = Double(minimumY) + Double(maximumY - minimumY) * ratio
    boundaries.append(Int64(crossing.rounded()))
  }
}

extension RasterTrapezoid {
  fileprivate func left(at y: Int64) -> Int64 {
    interpolate(start: leftAtMinimumY, end: leftAtMaximumY, at: y)
  }

  fileprivate func right(at y: Int64) -> Int64 {
    interpolate(start: rightAtMinimumY, end: rightAtMaximumY, at: y)
  }

  fileprivate func point(x: Int64, y: Int64) -> RasterPoint {
    RasterPoint(
      x: Double(x) / Double(FreeTypeFixedMath.outlineScale),
      y: Double(y) / Double(FreeTypeFixedMath.outlineScale)
    )
  }

  private func interpolate(start: Int64, end: Int64, at y: Int64) -> Int64 {
    guard maximumY != minimumY else { return start }
    let ratio = Double(y - minimumY) / Double(maximumY - minimumY)
    return Int64((Double(start) + Double(end - start) * ratio).rounded())
  }
}
