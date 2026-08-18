import Foundation

enum CoverageSpans {
  static func intersect(_ lhs: [CoverageSpan], _ rhs: [CoverageSpan]) -> [CoverageSpan] {
    var result: [CoverageSpan] = []
    result.reserveCapacity(min(lhs.count, rhs.count))
    var lhsIndex = 0
    var rhsIndex = 0
    while lhsIndex < lhs.count, rhsIndex < rhs.count {
      let left = lhs[lhsIndex]
      let right = rhs[rhsIndex]
      if left.y < right.y || (left.y == right.y && left.x + left.length <= right.x) {
        lhsIndex += 1
        continue
      }
      if right.y < left.y || (right.y == left.y && right.x + right.length <= left.x) {
        rhsIndex += 1
        continue
      }
      let start = max(left.x, right.x)
      let end = min(left.x + left.length, right.x + right.length)
      if left.y == right.y, start < end {
        result.append(CoverageSpan(
          x: start,
          y: left.y,
          length: end - start,
          coverage: UInt8((UInt16(left.coverage) * UInt16(right.coverage)) / 255)
        ))
      }
      if left.x + left.length < right.x + right.length {
        lhsIndex += 1
      } else {
        rhsIndex += 1
      }
    }
    return result
  }

  static func rectangle(_ rect: RasterRect, width: Int, height: Int) -> [CoverageSpan] {
    let minimumX = max(0, min(width, Int(rect.x.rounded(.up))))
    let maximumX = max(0, min(width, Int(rect.maxX.rounded(.down))))
    let minimumY = max(0, min(height, Int(rect.y.rounded(.up))))
    let maximumY = max(0, min(height, Int(rect.maxY.rounded(.down))))
    guard minimumX < maximumX, minimumY < maximumY else { return [] }
    return (minimumY..<maximumY).map {
      CoverageSpan(x: minimumX, y: $0, length: maximumX - minimumX, coverage: 255)
    }
  }
}
