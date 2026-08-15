//
//  NumericObjectConvertible.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation

protocol NumericObjectConvertible {

  var numericObject: Object { get throws }

}

extension Double: NumericObjectConvertible {

  var numericObject: Object {
    get throws { try .real(self) }
  }

}

extension Int32: NumericObjectConvertible {

  var numericObject: Object { .integer(self) }

}
