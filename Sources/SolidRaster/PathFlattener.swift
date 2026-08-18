import Foundation

enum PathFlattener {
  private static let maximumDepth = 16

  static func flatten(
    _ path: RasterPath,
    flatness: Double = 1.0 / 32.0
  ) throws(RasterError) -> FlattenedPath {
    guard flatness.isFinite, flatness > 0 else { throw .invalidGeometry }
    let toleranceSquared = flatness * flatness
    var subpaths: ContiguousArray<FlattenedPath.Subpath> = []
    var points: ContiguousArray<RasterPoint> = []
    var current: RasterPoint?

    func valid(_ point: RasterPoint) throws(RasterError) {
      guard point.x.isFinite, point.y.isFinite else { throw .invalidGeometry }
    }

    func finish(closed: Bool) {
      guard !points.isEmpty else { return }
      subpaths.append(.init(points: points, isClosed: closed))
      points.removeAll(keepingCapacity: true)
    }

    for element in path.elements {
      switch element {
      case .move(let point):
        try valid(point)
        finish(closed: false)
        points.append(point)
        current = point
      case .line(let point):
        try valid(point)
        guard current != nil else { throw .invalidGeometry }
        points.append(point)
        current = point
      case .cubic(let control1, let control2, let end):
        try valid(control1)
        try valid(control2)
        try valid(end)
        guard let start = current else { throw .invalidGeometry }
        try flattenCubic(
          start: start,
          control1: control1,
          control2: control2,
          end: end,
          toleranceSquared: toleranceSquared,
          depth: 0,
          into: &points
        )
        current = end
      case .close:
        finish(closed: true)
        current = nil
      }
    }
    finish(closed: false)
    return FlattenedPath(subpaths: subpaths)
  }

  private static func flattenCubic(
    start: RasterPoint,
    control1: RasterPoint,
    control2: RasterPoint,
    end: RasterPoint,
    toleranceSquared: Double,
    depth: Int,
    into points: inout ContiguousArray<RasterPoint>
  ) throws(RasterError) {
    let chordX = end.x - start.x
    let chordY = end.y - start.y
    let lengthSquared = chordX * chordX + chordY * chordY
    let distance1 = cross(control1.x - start.x, control1.y - start.y, chordX, chordY)
    let distance2 = cross(control2.x - start.x, control2.y - start.y, chordX, chordY)
    let flatEnough = lengthSquared == 0
      ? squaredDistance(start, control1) + squaredDistance(start, control2) <= toleranceSquared
      : (distance1 * distance1 + distance2 * distance2) <= toleranceSquared * lengthSquared
    if flatEnough || depth >= maximumDepth {
      points.append(end)
      return
    }

    let startControl = midpoint(start, control1)
    let controls = midpoint(control1, control2)
    let controlEnd = midpoint(control2, end)
    let leftControl = midpoint(startControl, controls)
    let rightControl = midpoint(controls, controlEnd)
    let middle = midpoint(leftControl, rightControl)
    try flattenCubic(
      start: start,
      control1: startControl,
      control2: leftControl,
      end: middle,
      toleranceSquared: toleranceSquared,
      depth: depth + 1,
      into: &points
    )
    try flattenCubic(
      start: middle,
      control1: rightControl,
      control2: controlEnd,
      end: end,
      toleranceSquared: toleranceSquared,
      depth: depth + 1,
      into: &points
    )
  }

  private static func midpoint(_ lhs: RasterPoint, _ rhs: RasterPoint) -> RasterPoint {
    RasterPoint(x: (lhs.x + rhs.x) * 0.5, y: (lhs.y + rhs.y) * 0.5)
  }

  private static func cross(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    ax * by - ay * bx
  }

  private static func squaredDistance(_ lhs: RasterPoint, _ rhs: RasterPoint) -> Double {
    let x = lhs.x - rhs.x
    let y = lhs.y - rhs.y
    return x * x + y * y
  }
}
