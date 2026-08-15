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
      guard let number = arg.value as? NumericConvertible else {
        throw Error.typeCheck
      }
      guard number.real >= 0 else {
        throw Error.rangeCheck
      }
      let result: Object = try .real(number.real.squareRoot())
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
      guard let base = args[1].value as? NumericConvertible,
        let exponent = args[0].value as? NumericConvertible
      else {
        throw Error.typeCheck
      }
      let result = try NumericSemantics.power(base.real, exponent.real)
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
      guard let number = arg.value as? NumericConvertible else {
        throw Error.typeCheck
      }
      guard number.real > 0 else {
        throw Error.rangeCheck
      }
      let result: Object = try .real(log(number.real))
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
      guard let number = arg.value as? NumericConvertible else {
        throw Error.typeCheck
      }
      guard number.real > 0 else {
        throw Error.rangeCheck
      }
      let result: Object = try .real(log10(number.real))
      context.operands.push(result)
    }
  }
}
