// A Swift port of FreeType's exact-coverage ftgrays line-cell algorithm.
// See Documentation/SolidRasterProvenance.md and Vendor/PlutoVG/source/FTL.TXT.

import Foundation

enum GrayRasterizer {
  private static let pixelBits: Int64 = 8
  private static let onePixel: Int64 = 1 << pixelBits

  private struct Worker: ~Copyable {
    let width: Int
    let height: Int
    var arena: RasterCellArena
    var ex: Int64 = 0
    var ey: Int64 = 0
    var area: Int64 = 0
    var cover: Int64 = 0
    var invalid = true

    mutating func move(to point: RasterPoint) throws(RasterError) {
      try recordCell()
      let x = try FreeTypeFixedMath.rasterCoordinate(
        fromOutline: FreeTypeFixedMath.outlineCoordinate(point.x)
      )
      let y = try FreeTypeFixedMath.rasterCoordinate(
        fromOutline: FreeTypeFixedMath.outlineCoordinate(point.y)
      )
      ex = x >> GrayRasterizer.pixelBits
      ey = y >> GrayRasterizer.pixelBits
      area = 0
      cover = 0
      invalid = true
      try setCell(x: ex, y: ey)
    }

    mutating func line(to point: RasterPoint, from current: RasterPoint) throws(RasterError) {
      let x1 = try FreeTypeFixedMath.rasterCoordinate(
        fromOutline: FreeTypeFixedMath.outlineCoordinate(current.x)
      )
      let y1 = try FreeTypeFixedMath.rasterCoordinate(
        fromOutline: FreeTypeFixedMath.outlineCoordinate(current.y)
      )
      let x2 = try FreeTypeFixedMath.rasterCoordinate(
        fromOutline: FreeTypeFixedMath.outlineCoordinate(point.x)
      )
      let y2 = try FreeTypeFixedMath.rasterCoordinate(
        fromOutline: FreeTypeFixedMath.outlineCoordinate(point.y)
      )
      try renderLine(fromX: x1, fromY: y1, toX: x2, toY: y2)
    }

    mutating func finish() throws(RasterError) {
      try recordCell()
    }

    mutating func renderLine(
      fromX: Int64,
      fromY: Int64,
      toX: Int64,
      toY: Int64
    ) throws(RasterError) {
      var eye1 = fromY >> GrayRasterizer.pixelBits
      let eye2 = toY >> GrayRasterizer.pixelBits
      if (eye1 >= Int64(height) && eye2 >= Int64(height)) || (eye1 < 0 && eye2 < 0) {
        return
      }
      let fractionY1 = fromY & (GrayRasterizer.onePixel - 1)
      let fractionY2 = toY & (GrayRasterizer.onePixel - 1)
      if eye1 == eye2 {
        try renderScanline(y: eye1, x1: fromX, y1: fractionY1, x2: toX, y2: fractionY2)
        return
      }

      let deltaX = toX - fromX
      var deltaY = toY - fromY
      if deltaX == 0 {
        let x = fromX >> GrayRasterizer.pixelBits
        let twiceFractionX = (fromX & (GrayRasterizer.onePixel - 1)) << 1
        let first = deltaY > 0 ? GrayRasterizer.onePixel : 0
        var delta = first - fractionY1
        area += twiceFractionX * delta
        cover += delta
        delta = first + first - GrayRasterizer.onePixel
        let completeArea = twiceFractionX * delta
        if deltaY < 0 {
          eye1 -= 1
          try setCell(x: x, y: eye1)
          while eye1 > eye2 {
            area += completeArea
            cover += delta
            eye1 -= 1
            try setCell(x: x, y: eye1)
          }
        } else {
          eye1 += 1
          try setCell(x: x, y: eye1)
          while eye1 < eye2 {
            area += completeArea
            cover += delta
            eye1 += 1
            try setCell(x: x, y: eye1)
          }
        }
        delta = fractionY2 - GrayRasterizer.onePixel + first
        area += twiceFractionX * delta
        cover += delta
        return
      }

      let first: Int64
      let increment: Int64
      var product: Int64
      if deltaY > 0 {
        product = (GrayRasterizer.onePixel - fractionY1) * deltaX
        first = GrayRasterizer.onePixel
        increment = 1
      } else {
        product = fractionY1 * deltaX
        first = 0
        increment = -1
        deltaY = -deltaY
      }
      var division = FreeTypeFixedMath.floorDivide(product, by: deltaY)
      var x = fromX + division.quotient
      try renderScanline(y: eye1, x1: fromX, y1: fractionY1, x2: x, y2: first)
      eye1 += increment
      try setCell(x: x >> GrayRasterizer.pixelBits, y: eye1)
      if eye1 != eye2 {
        product = GrayRasterizer.onePixel * deltaX
        let step = FreeTypeFixedMath.floorDivide(product, by: deltaY)
        repeat {
          var delta = step.quotient
          division.remainder += step.remainder
          if division.remainder >= deltaY {
            division.remainder -= deltaY
            delta += 1
          }
          let nextX = x + delta
          try renderScanline(
            y: eye1,
            x1: x,
            y1: GrayRasterizer.onePixel - first,
            x2: nextX,
            y2: first
          )
          x = nextX
          eye1 += increment
          try setCell(x: x >> GrayRasterizer.pixelBits, y: eye1)
        } while eye1 != eye2
      }
      try renderScanline(
        y: eye1,
        x1: x,
        y1: GrayRasterizer.onePixel - first,
        x2: toX,
        y2: fractionY2
      )
    }

    mutating func renderScanline(
      y: Int64,
      x1: Int64,
      y1: Int64,
      x2: Int64,
      y2: Int64
    ) throws(RasterError) {
      var pixelX1 = x1 >> GrayRasterizer.pixelBits
      let pixelX2 = x2 >> GrayRasterizer.pixelBits
      if y1 == y2 {
        try setCell(x: pixelX2, y: y)
        return
      }
      var fractionX1 = x1 & (GrayRasterizer.onePixel - 1)
      var currentY = y1
      let fractionX2 = x2 & (GrayRasterizer.onePixel - 1)
      if pixelX1 == pixelX2 {
        let deltaY = y2 - y1
        area += (fractionX1 + fractionX2) * deltaY
        cover += deltaY
        return
      }

      var deltaX = x2 - x1
      let deltaY = y2 - y1
      let first: Int64
      let increment: Int64
      var product: Int64
      if deltaX > 0 {
        product = (GrayRasterizer.onePixel - fractionX1) * deltaY
        first = GrayRasterizer.onePixel
        increment = 1
      } else {
        product = fractionX1 * deltaY
        first = 0
        increment = -1
        deltaX = -deltaX
      }
      var division = FreeTypeFixedMath.floorDivide(product, by: deltaX)
      area += (fractionX1 + first) * division.quotient
      cover += division.quotient
      currentY += division.quotient
      pixelX1 += increment
      try setCell(x: pixelX1, y: y)
      if pixelX1 != pixelX2 {
        let step = FreeTypeFixedMath.floorDivide(GrayRasterizer.onePixel * deltaY, by: deltaX)
        repeat {
          var delta = step.quotient
          division.remainder += step.remainder
          if division.remainder >= deltaX {
            division.remainder -= deltaX
            delta += 1
          }
          area += GrayRasterizer.onePixel * delta
          cover += delta
          currentY += delta
          pixelX1 += increment
          try setCell(x: pixelX1, y: y)
        } while pixelX1 != pixelX2
      }
      fractionX1 = GrayRasterizer.onePixel - first
      let remainingY = y2 - currentY
      area += (fractionX1 + fractionX2) * remainingY
      cover += remainingY
    }

    mutating func setCell(x: Int64, y: Int64) throws(RasterError) {
      let normalizedX = min(Int64(width), max(-1, x))
      if normalizedX != ex || y != ey {
        try recordCell()
        area = 0
        cover = 0
        ex = normalizedX
        ey = y
      }
      invalid = y < 0 || y >= Int64(height) || normalizedX >= Int64(width)
    }

    mutating func recordCell() throws(RasterError) {
      guard !invalid, area != 0 || cover != 0 else { return }
      try arena.record(column: Int(ex), row: Int(ey), area: area, cover: cover)
    }
  }

  static func rasterize(
    _ path: RasterPath,
    rule: RasterFillRule,
    width: Int,
    height: Int,
    limits: RasterLimits
  ) throws(RasterError) -> [CoverageSpan] {
    let flattened = try PathFlattener.flatten(path)
    var worker = try Worker(
      width: width,
      height: height,
      arena: RasterCellArena(height: height, maximumScratchBytes: limits.maximumScratchBytes)
    )
    for subpath in flattened.subpaths where subpath.points.count > 1 {
      let first = subpath.points[0]
      try worker.move(to: first)
      var current = first
      for point in subpath.points.dropFirst() {
        try worker.line(to: point, from: current)
        current = point
      }
      if current != first {
        try worker.line(to: first, from: current)
      }
    }
    try worker.finish()
    return worker.arena.sweep(rule: rule, width: width)
  }
}
