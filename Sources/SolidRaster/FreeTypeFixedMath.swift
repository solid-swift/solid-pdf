// Derived from FreeType's ftgrays.c and fttrigon.c. See
// Documentation/SolidRasterProvenance.md and Vendor/PlutoVG/source/FTL.TXT.

import Foundation

enum FreeTypeFixedMath {
  static let outlineScale: Int64 = 64
  static let rasterScale: Int64 = 256

  static func outlineCoordinate(_ value: Double) throws(RasterError) -> Int64 {
    guard value.isFinite else { throw .invalidGeometry }
    let scaled = value * Double(outlineScale)
    guard scaled >= Double(Int64.min), scaled <= Double(Int64.max) else {
      throw .coordinateOverflow
    }
    return Int64(scaled.rounded())
  }

  static func rasterCoordinate(fromOutline value: Int64) throws(RasterError) -> Int64 {
    let (result, overflow) = value.multipliedReportingOverflow(by: rasterScale / outlineScale)
    guard !overflow else { throw .coordinateOverflow }
    return result
  }

  static func floorDivide(_ dividend: Int64, by divisor: Int64) -> (quotient: Int64, remainder: Int64) {
    var quotient = dividend / divisor
    var remainder = dividend % divisor
    if remainder < 0 {
      quotient -= 1
      remainder += divisor
    }
    return (quotient, remainder)
  }

  static func multiplyDivide(_ a: Int64, _ b: Int64, _ c: Int64) -> Int64 {
    guard c != 0 else { return Int64.max }
    let product = a.multipliedReportingOverflow(by: b)
    guard !product.overflow else { return (a < 0) == (b < 0) ? Int64.max : Int64.min }
    let adjustment = abs(c) >> 1
    return product.partialValue >= 0
      ? (product.partialValue + adjustment) / c
      : (product.partialValue - adjustment) / c
  }
}
