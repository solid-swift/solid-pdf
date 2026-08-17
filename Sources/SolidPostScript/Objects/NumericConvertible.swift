//
//  NumericConvertible.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
internal protocol NumericConvertible: ObjectValue {

  var real: Double { get }
  var integer: Int32 { get throws }

}

extension RealValue: NumericConvertible {

  var real: Double { value }
  var integer: Int32 {
    get throws {
      guard let integer = Int32(exactly: value.rounded(.towardZero)) else {
        throw Error.rangeCheck
      }
      return integer
    }
  }

}

extension IntegerValue: NumericConvertible {

  var real: Double { Double(value) }
  var integer: Int32 { value }

}
