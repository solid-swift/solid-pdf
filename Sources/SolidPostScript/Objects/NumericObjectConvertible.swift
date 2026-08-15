//
//  NumericObjectConvertible.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation

protocol NumericObjectConvertible {

  var numericObject: Object { get }

}

extension Double: NumericObjectConvertible {

  var numericObject: Object { .real(self) }

}

extension Int: NumericObjectConvertible {

  var numericObject: Object { .integer(self) }

}
