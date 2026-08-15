//
//  ArithmeticOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Operators {

  static let arithmeticOps: [OperatorValue] = [
    Add.instance,
    Subtract.instance,
    Multiply.instance,
    Divide.instance,
    IntegerDivide.instance,
    Modulus.instance,
    AbsoluteValue.instance,
    Negative.instance,
    Ceiling.instance,
    Floor.instance,
    Round.instance,
    Truncate.instance,
  ]

  /// Implements the PostScript `add` operator.
  public enum Add: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["add"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .integer(l.value + r.value)
        case (let l as RealValue, let r as RealValue):
          .real(l.value + r.value)
        case (let l as NumericConvertible, let r as NumericConvertible):
          .real(try l.real + r.real)
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `sub` operator.
  public enum Subtract: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["sub"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .integer(l.value - r.value)
        case (let l as RealValue, let r as RealValue):
          .real(l.value - r.value)
        case (let l as NumericConvertible, let r as NumericConvertible):
          .real(try l.real - r.real)
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `mul` operator.
  public enum Multiply: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["mul"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .integer(l.value * r.value)
        case (let l as RealValue, let r as RealValue):
          .real(l.value * r.value)
        case (let l as NumericConvertible, let r as NumericConvertible):
          .real(try l.real * r.real)
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `div` operator.
  public enum Divide: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["div"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .real(try l.real / r.real)
        case (let l as RealValue, let r as RealValue):
          .real(l.value / r.value)
        case (let l as NumericConvertible, let r as NumericConvertible):
          .real(try l.real / r.real)
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `idiv` operator.
  public enum IntegerDivide: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["idiv"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .integer(l.value / r.value)
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `mod` operator.
  public enum Modulus: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["mod"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .integer(l.value % r.value)
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `abs` operator.
  public enum AbsoluteValue: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["abs"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case (let l as IntegerValue):
          if l.value != .min {
            .integer(abs(l.value))
          } else {
            .real(abs(try l.real))
          }
        case (let l as RealValue):
          .real(abs(l.value))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `neg` operator.
  public enum Negative: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["neg"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case (let l as IntegerValue):
          if l.value != .min {
            .integer(-l.value)
          } else {
            .real(try -l.real)
          }
        case (let l as RealValue):
          .real(-l.value)
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `ceiling` operator.
  public enum Ceiling: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["ceiling"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case (is IntegerValue):
          arg
        case (let l as RealValue):
          .real(ceil(l.value))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `floor` operator.
  public enum Floor: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["floor"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case (is IntegerValue):
          arg
        case (let l as RealValue):
          .real(floor(l.value))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `round` operator.
  public enum Round: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["round"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case (is IntegerValue):
          arg
        case (let l as RealValue):
          .real(round(l.value))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `truncate` operator.
  public enum Truncate: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["truncate"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case (is IntegerValue):
          arg
        case (let l as RealValue):
          .real(trunc(l.value))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

}
