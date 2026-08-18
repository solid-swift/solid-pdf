import Foundation

enum DashProcessor {
  static func apply(
    _ subpaths: ContiguousArray<FlattenedPath.Subpath>,
    pattern sourcePattern: [Double],
    phase sourcePhase: Double
  ) throws(RasterError) -> ContiguousArray<FlattenedPath.Subpath> {
    guard !sourcePattern.isEmpty else { return subpaths }
    guard sourcePattern.allSatisfy({ $0.isFinite && $0 >= 0 }), sourcePattern.contains(where: { $0 > 0 }) else {
      throw .invalidGeometry
    }
    let pattern = sourcePattern.count.isMultiple(of: 2) ? sourcePattern : sourcePattern + sourcePattern
    let total = pattern.reduce(0, +)
    guard total.isFinite, total > 0, sourcePhase.isFinite else { throw .invalidGeometry }
    var phase = sourcePhase.truncatingRemainder(dividingBy: total)
    if phase < 0 { phase += total }
    var initialIndex = 0
    while phase >= pattern[initialIndex], pattern[initialIndex] > 0 {
      phase -= pattern[initialIndex]
      initialIndex = (initialIndex + 1) % pattern.count
    }

    var output: ContiguousArray<FlattenedPath.Subpath> = []
    for subpath in subpaths where subpath.points.count > 1 {
      var points = subpath.points
      if subpath.isClosed, let first = points.first, points.last != first { points.append(first) }
      var patternIndex = initialIndex
      var remaining = pattern[patternIndex] - phase
      var drawing = patternIndex.isMultiple(of: 2)
      var active: ContiguousArray<RasterPoint> = []
      for pair in zip(points, points.dropFirst()) {
        let start = pair.0
        let end = pair.1
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length.isFinite else { throw .invalidGeometry }
        if length == 0 { continue }
        var consumed = 0.0
        var current = start
        while consumed < length {
          while remaining == 0 {
            if drawing, active.count > 1 { output.append(.init(points: active, isClosed: false)) }
            active.removeAll(keepingCapacity: true)
            patternIndex = (patternIndex + 1) % pattern.count
            remaining = pattern[patternIndex]
            drawing = patternIndex.isMultiple(of: 2)
          }
          let step = min(remaining, length - consumed)
          let fraction = (consumed + step) / length
          let next = RasterPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
          if drawing {
            if active.isEmpty { active.append(current) }
            active.append(next)
          }
          current = next
          consumed += step
          remaining -= step
          if remaining <= Double.ulpOfOne * max(1, length) { remaining = 0 }
        }
      }
      if drawing, active.count > 1 { output.append(.init(points: active, isClosed: false)) }
    }
    return output
  }
}
