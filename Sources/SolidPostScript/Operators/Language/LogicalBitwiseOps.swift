//
//  LogicalBitwiseOps.swift
//
//
//  Created by Kevin Wooten on 6/29/24.
//

import Foundation

extension Operators {

  static let logicalBitwiseOps: [OperatorValue] = [
    And.instance,
    Not.instance,
    Or.instance,
    Xor.instance,
    BitShift.instance,
  ]

  /// Implements the PostScript `and` operator.
  public enum And: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["and"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op1, op2) = try context.operands.pop2()

      switch (op1.value, op2.value) {
      case (let bool1 as BooleanValue, let bool2 as BooleanValue):
        context.operands.push(.boolean(bool1.value && bool2.value))

      case (let int1 as IntegerValue, let int2 as IntegerValue):
        context.operands.push(.integer(int1.value & int2.value))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `not` operator.
  public enum Not: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["not"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op1 = try context.operands.pop()

      switch op1.value {
      case let bool1 as BooleanValue:
        context.operands.push(.boolean(!bool1.value))

      case let int1 as IntegerValue:
        context.operands.push(.integer(~int1.value))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `or` operator.
  public enum Or: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["or"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op1, op2) = try context.operands.pop2()

      switch (op1.value, op2.value) {
      case (let bool1 as BooleanValue, let bool2 as BooleanValue):
        context.operands.push(.boolean(bool1.value || bool2.value))

      case (let int1 as IntegerValue, let int2 as IntegerValue):
        context.operands.push(.integer(int1.value | int2.value))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `xor` operator.
  public enum Xor: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["xor"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op1, op2) = try context.operands.pop2()

      switch (op1.value, op2.value) {
      case (let bool1 as BooleanValue, let bool2 as BooleanValue):
        context.operands.push(.boolean(bool1.value != bool2.value))

      case (let int1 as IntegerValue, let int2 as IntegerValue):
        context.operands.push(.integer(int1.value ^ int2.value))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `bitshift` operator.
  public enum BitShift: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["bitshift"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (shift, int) = try context.operands.popAs((IntegerValue, IntegerValue).self)

      let shiftCount = Int64(shift.value)
      guard abs(shiftCount) < 32 else {
        context.operands.push(.integer(0))
        return
      }

      let bits = UInt32(bitPattern: int.value)
      let shifted =
        if shiftCount >= 0 {
          bits << UInt32(shiftCount)
        } else {
          bits >> UInt32(-shiftCount)
        }
      context.operands.push(.integer(Int32(bitPattern: shifted)))
    }
  }

}
