//
//  Range.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

extension Range {

  internal func select<R: RangeExpression, C: Collection>(
    subRange: R,
    in collection: C
  ) throws -> Range<C.Index> where C.Index == Bound, R.Bound == UInt {

    let count = collection.distance(from: lowerBound, to: upperBound)
    let range = subRange.relative(to: 0..<UInt(count))

    guard range.lowerBound <= UInt(count), range.upperBound <= UInt(count) else {
      throw Error.rangeCheck
    }

    let startIndex = collection.index(lowerBound, offsetBy: Int(range.lowerBound))
    let endIndex = collection.index(lowerBound, offsetBy: Int(range.upperBound))
    return startIndex..<endIndex
  }
}
