//
//  NumericConvertible.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
import SolidCore

internal protocol NumericConvertible: ObjectValue {

  var real: Double { get throws }
  var integer: Int { get throws }

}

extension RealValue: NumericConvertible {

  var real: Double { value }
  var integer: Int {
    get throws { try Int(exactly: value.rounded()).unwrap(or: Error.rangeCheck) }
  }

}

extension IntegerValue: NumericConvertible {

  var real: Double {
    get throws { try Double(exactly: value).unwrap(or: Error.rangeCheck) }
  }
  var integer: Int { value }

}
