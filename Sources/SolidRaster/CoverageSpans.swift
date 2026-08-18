import Foundation

enum CoverageSpans {
  static func intersect(
    _ lhs: borrowing Span<CoverageSpan>,
    _ rhs: borrowing Span<CoverageSpan>,
    into result: inout [CoverageSpan]
  ) {
    result.removeAll(keepingCapacity: true)
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
  }

  static func rectangle(
    _ rect: RasterRect,
    width: Int,
    height: Int,
    into result: inout [CoverageSpan]
  ) {
    result.removeAll(keepingCapacity: true)
    let minimumX = max(0, min(width, Int(rect.x.rounded(.up))))
    let maximumX = max(0, min(width, Int(rect.maxX.rounded(.down))))
    let minimumY = max(0, min(height, Int(rect.y.rounded(.up))))
    let maximumY = max(0, min(height, Int(rect.maxY.rounded(.down))))
    guard minimumX < maximumX, minimumY < maximumY else { return }
    result.reserveCapacity(maximumY - minimumY)
    for row in minimumY..<maximumY {
      result.append(CoverageSpan(
        x: minimumX,
        y: row,
        length: maximumX - minimumX,
        coverage: 255
      ))
    }
  }

  static func integralRectangle(in path: borrowing RasterPath) -> RasterRect? {
    guard path.elements.count == 5,
      case .move(let first) = path.elements[0],
      case .line(let second) = path.elements[1],
      case .line(let third) = path.elements[2],
      case .line(let fourth) = path.elements[3],
      case .close = path.elements[4],
      isIntegral(first),
      isIntegral(second),
      isIntegral(third),
      isIntegral(fourth),
      isAxisAligned(first, second),
      isAxisAligned(second, third),
      isAxisAligned(third, fourth),
      isAxisAligned(fourth, first)
    else { return nil }

    let minimumX = min(first.x, second.x, third.x, fourth.x)
    let maximumX = max(first.x, second.x, third.x, fourth.x)
    let minimumY = min(first.y, second.y, third.y, fourth.y)
    let maximumY = max(first.y, second.y, third.y, fourth.y)
    guard minimumX < maximumX,
      minimumY < maximumY,
      isCorner(first, minimumX: minimumX, maximumX: maximumX, minimumY: minimumY, maximumY: maximumY),
      isCorner(second, minimumX: minimumX, maximumX: maximumX, minimumY: minimumY, maximumY: maximumY),
      isCorner(third, minimumX: minimumX, maximumX: maximumX, minimumY: minimumY, maximumY: maximumY),
      isCorner(fourth, minimumX: minimumX, maximumX: maximumX, minimumY: minimumY, maximumY: maximumY),
      first != second,
      first != third,
      first != fourth,
      second != third,
      second != fourth,
      third != fourth
    else { return nil }
    return RasterRect(
      x: minimumX,
      y: minimumY,
      width: maximumX - minimumX,
      height: maximumY - minimumY
    )
  }

  private static func isIntegral(_ point: RasterPoint) -> Bool {
    point.x.isFinite
      && point.y.isFinite
      && point.x.rounded() == point.x
      && point.y.rounded() == point.y
  }

  private static func isAxisAligned(_ start: RasterPoint, _ end: RasterPoint) -> Bool {
    (start.x == end.x) != (start.y == end.y)
  }

  private static func isCorner(
    _ point: RasterPoint,
    minimumX: Double,
    maximumX: Double,
    minimumY: Double,
    maximumY: Double
  ) -> Bool {
    (point.x == minimumX || point.x == maximumX)
      && (point.y == minimumY || point.y == maximumY)
  }
}
