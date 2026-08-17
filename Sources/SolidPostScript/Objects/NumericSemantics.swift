//
//  NumericSemantics.swift
//
//

import Foundation

enum NumericSemantics {

  static func integerOrReal(_ value: Int64) throws -> Object {
    if let integer = Int32(exactly: value) {
      return .integer(integer)
    }
    return try .real(Double(value))
  }

  static func integer<T: BinaryInteger>(
    validating value: T,
    error: Error = .rangeCheck
  ) throws -> Object {
    guard let integer = Int32(exactly: value) else {
      throw error
    }
    return .integer(integer)
  }

  static func multiply(_ lhs: Double, _ rhs: Double) throws -> Object {
    let result = lhs * rhs
    return try .real(result, underflowed: result == 0 && lhs != 0 && rhs != 0)
  }

  static func divide(_ dividend: Double, by divisor: Double) throws -> Object {
    guard divisor != 0 else {
      throw Error.undefinedResult
    }
    let result = dividend / divisor
    return try .real(result, underflowed: result == 0 && dividend != 0)
  }

  static func power(_ base: Double, _ exponent: Double) throws -> Object {
    let result = pow(base, exponent)
    let underflowed = result == 0 && base != 0
    return try .real(result, underflowed: underflowed)
  }
}
