//
//  RootExpLogOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Operators {

  static let mathOps: [OperatorValue] = [
    SquareRoot.instance,
    Exponent.instance,
    NaturalLogarithm.instance,
    Logarithm.instance,
  ]

  /// Implements the PostScript `sqrt` operator.
  public enum SquareRoot: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["sqrt"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case let l as IntegerValue:
          .real(try l.real.squareRoot())
        case let l as RealValue:
          .real(l.value.squareRoot())
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `exp` operator.
  public enum Exponent: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["exp"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .real(try pow(l.real, r.real))
        case (let l as RealValue, let r as RealValue):
          .real(pow(l.value, r.value))
        case (let l as NumericConvertible, let r as NumericConvertible):
          .real(try pow(l.real, r.real))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `ln` operator.
  public enum NaturalLogarithm: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["ln"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case let l as IntegerValue:
          .real(try log(l.real))
        case let l as RealValue:
          .real(log(l.value))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `log` operator.
  public enum Logarithm: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["log"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case let l as IntegerValue:
          .real(try log10(l.real))
        case let l as RealValue:
          .real(log10(l.value))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }
}
