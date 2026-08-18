// The cap, join, and fixed-miter construction follows FreeType's ftstroke.c.
// See Documentation/SolidRasterProvenance.md and Vendor/PlutoVG/source/FTL.TXT.

import Foundation

enum PathStroker {
  private struct Vector {
    var x: Double
    var y: Double

    static func + (lhs: Self, rhs: Self) -> Self { Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: Self, rhs: Double) -> Self { Self(x: lhs.x * rhs, y: lhs.y * rhs) }
  }

  static func stroke(
    _ path: RasterPath,
    style: RasterStrokeStyle,
    transform: RasterAffineTransform
  ) throws(RasterError) -> RasterPath {
    guard style.width.isFinite,
      style.width >= 0,
      style.miterLimit.isFinite,
      style.miterLimit >= 1,
      [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite)
    else { throw .invalidGeometry }
    guard style.width > 0 else { return RasterPath() }
    let flattened = try PathFlattener.flatten(path)
    let subpaths = try DashProcessor.apply(
      flattened.subpaths,
      pattern: style.dash,
      phase: style.dashPhase
    )
    let halfWidth = style.width * 0.5
    var elements: [RasterPath.Element] = []
    elements.reserveCapacity(min(1_000_000, path.elements.count * 12))
    for subpath in subpaths where subpath.points.count > 1 {
      try appendStroke(
        subpath,
        halfWidth: halfWidth,
        style: style,
        transform: transform,
        into: &elements
      )
    }
    return RasterPath(elements: elements)
  }

  private static func appendStroke(
    _ subpath: FlattenedPath.Subpath,
    halfWidth: Double,
    style: RasterStrokeStyle,
    transform: RasterAffineTransform,
    into elements: inout [RasterPath.Element]
  ) throws(RasterError) {
    var points = subpath.points
    if subpath.isClosed, let first = points.first, points.last != first { points.append(first) }
    var segments: [(start: Vector, end: Vector, unit: Vector, normal: Vector)] = []
    for pair in zip(points, points.dropFirst()) {
      let start = Vector(x: pair.0.x, y: pair.0.y)
      let end = Vector(x: pair.1.x, y: pair.1.y)
      let delta = end - start
      let length = hypot(delta.x, delta.y)
      guard length.isFinite else { throw .invalidGeometry }
      guard length > 0 else { continue }
      let unit = delta * (1 / length)
      segments.append((start, end, unit, Vector(x: -unit.y, y: unit.x)))
    }
    guard let firstSegment = segments.first, let lastSegment = segments.last else { return }

    for segment in segments {
      let offset = segment.normal * halfWidth
      appendPolygon([
        segment.start + offset,
        segment.end + offset,
        segment.end - offset,
        segment.start - offset,
      ], transform: transform, into: &elements)
    }

    if subpath.isClosed {
      for index in segments.indices {
        let previous = segments[(index + segments.count - 1) % segments.count]
        let next = segments[index]
        appendJoin(
          at: next.start,
          previous: previous,
          next: next,
          halfWidth: halfWidth,
          style: style,
          transform: transform,
          into: &elements
        )
      }
    } else {
      for index in 1..<segments.count {
        appendJoin(
          at: segments[index].start,
          previous: segments[index - 1],
          next: segments[index],
          halfWidth: halfWidth,
          style: style,
          transform: transform,
          into: &elements
        )
      }
      appendCap(
        at: firstSegment.start,
        outward: firstSegment.unit * -1,
        normal: firstSegment.normal,
        halfWidth: halfWidth,
        cap: style.cap,
        transform: transform,
        into: &elements
      )
      appendCap(
        at: lastSegment.end,
        outward: lastSegment.unit,
        normal: lastSegment.normal,
        halfWidth: halfWidth,
        cap: style.cap,
        transform: transform,
        into: &elements
      )
    }
  }

  private static func appendJoin(
    at point: Vector,
    previous: (start: Vector, end: Vector, unit: Vector, normal: Vector),
    next: (start: Vector, end: Vector, unit: Vector, normal: Vector),
    halfWidth: Double,
    style: RasterStrokeStyle,
    transform: RasterAffineTransform,
    into elements: inout [RasterPath.Element]
  ) {
    let turn = cross(previous.unit, next.unit)
    guard abs(turn) > 1e-12 else { return }
    if style.join == .round {
      appendCircle(center: point, radius: halfWidth, transform: transform, into: &elements)
      return
    }
    let side = turn > 0 ? 1.0 : -1.0
    let outer1 = point + previous.normal * (halfWidth * side)
    let outer2 = point + next.normal * (halfWidth * side)
    if style.join == .miter,
      let miter = lineIntersection(
        point: outer1,
        direction: previous.unit,
        otherPoint: outer2,
        otherDirection: next.unit
      ),
      hypot(miter.x - point.x, miter.y - point.y) <= halfWidth * style.miterLimit
    {
      appendPolygon([outer1, miter, outer2], transform: transform, into: &elements)
    } else {
      appendPolygon([point, outer1, outer2], transform: transform, into: &elements)
    }
  }

  private static func appendCap(
    at point: Vector,
    outward: Vector,
    normal: Vector,
    halfWidth: Double,
    cap: RasterLineCap,
    transform: RasterAffineTransform,
    into elements: inout [RasterPath.Element]
  ) {
    switch cap {
    case .butt:
      break
    case .round:
      appendCircle(center: point, radius: halfWidth, transform: transform, into: &elements)
    case .square:
      let offset = normal * halfWidth
      let extensionVector = outward * halfWidth
      appendPolygon([
        point + offset,
        point + offset + extensionVector,
        point - offset + extensionVector,
        point - offset,
      ], transform: transform, into: &elements)
    }
  }

  private static func appendCircle(
    center: Vector,
    radius: Double,
    transform: RasterAffineTransform,
    into elements: inout [RasterPath.Element]
  ) {
    let segmentCount = max(12, min(128, Int((Double.pi * radius).rounded(.up))))
    let points = (0..<segmentCount).map { index in
      let angle = Double(index) * 2 * .pi / Double(segmentCount)
      return Vector(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    appendPolygon(points, transform: transform, into: &elements)
  }

  private static func appendPolygon(
    _ points: [Vector],
    transform: RasterAffineTransform,
    into elements: inout [RasterPath.Element]
  ) {
    guard let first = points.first else { return }
    elements.append(.move(to: transformed(first, by: transform)))
    for point in points.dropFirst() {
      elements.append(.line(to: transformed(point, by: transform)))
    }
    elements.append(.close)
  }

  private static func transformed(_ vector: Vector, by transform: RasterAffineTransform) -> RasterPoint {
    transform.transform(RasterPoint(x: vector.x, y: vector.y))
  }

  private static func lineIntersection(
    point: Vector,
    direction: Vector,
    otherPoint: Vector,
    otherDirection: Vector
  ) -> Vector? {
    let denominator = cross(direction, otherDirection)
    guard abs(denominator) > 1e-12 else { return nil }
    let distance = cross(otherPoint - point, otherDirection) / denominator
    return point + direction * distance
  }

  private static func cross(_ lhs: Vector, _ rhs: Vector) -> Double {
    lhs.x * rhs.y - lhs.y * rhs.x
  }
}
