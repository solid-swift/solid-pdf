//
//  RelationalOps.swift
//
//
//  Created by Kevin Wooten on 6/29/24.
//

import Foundation

extension Operators {

  static let relationalOps: [OperatorValue] = [
    Equal.instance,
    NotEqual.instance,
    GreaterThanOrEqual.instance,
    GreaterThan.instance,
    LesserThanOrEqual.instance,
    LesserThan.instance,
  ]

  /// Implements the PostScript `eq` operator.
  public enum Equal: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["eq"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op2, op1) = try context.operands.pop2()

      context.operands.push(.boolean(try op1.value.equals(op2.value)))
    }
  }

  /// Implements the PostScript `ne` operator.
  public enum NotEqual: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["ne"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op2, op1) = try context.operands.pop2()

      context.operands.push(.boolean(try !op1.value.equals(op2.value)))
    }
  }

  /// Implements the PostScript `ge` operator.
  public enum GreaterThanOrEqual: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["ge"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op2, op1) = try context.operands.pop2()

      switch (op1.value, op2.value) {
      case (let str1 as StringValue, let str2 as StringValue):
        let result = try str1.compareReadable(str2)
        context.operands.push(.boolean(result == .orderedSame || result == .orderedDescending))

      case (let num1 as IntegerValue, let num2 as IntegerValue):
        context.operands.push(.boolean(num1.value >= num2.value))

      case (let num1 as RealValue, let num2 as RealValue):
        context.operands.push(.boolean(num1.value >= num2.value))

      case (let num1 as NumericConvertible, let num2 as NumericConvertible):
        context.operands.push(.boolean(num1.real >= num2.real))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `gt` operator.
  public enum GreaterThan: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["gt"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op2, op1) = try context.operands.pop2()

      switch (op1.value, op2.value) {
      case (let str1 as StringValue, let str2 as StringValue):
        context.operands.push(.boolean(try str1.compareReadable(str2) == .orderedDescending))

      case (let num1 as IntegerValue, let num2 as IntegerValue):
        context.operands.push(.boolean(num1.value > num2.value))

      case (let num1 as RealValue, let num2 as RealValue):
        context.operands.push(.boolean(num1.value > num2.value))

      case (let num1 as NumericConvertible, let num2 as NumericConvertible):
        context.operands.push(.boolean(num1.real > num2.real))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `le` operator.
  public enum LesserThanOrEqual: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["le"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op2, op1) = try context.operands.pop2()

      switch (op1.value, op2.value) {
      case (let str1 as StringValue, let str2 as StringValue):
        let result = try str1.compareReadable(str2)
        context.operands.push(.boolean(result == .orderedSame || result == .orderedAscending))

      case (let num1 as IntegerValue, let num2 as IntegerValue):
        context.operands.push(.boolean(num1.value <= num2.value))

      case (let num1 as RealValue, let num2 as RealValue):
        context.operands.push(.boolean(num1.value <= num2.value))

      case (let num1 as NumericConvertible, let num2 as NumericConvertible):
        context.operands.push(.boolean(num1.real <= num2.real))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `lt` operator.
  public enum LesserThan: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["lt"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (op2, op1) = try context.operands.pop2()

      switch (op1.value, op2.value) {
      case (let str1 as StringValue, let str2 as StringValue):
        context.operands.push(.boolean(try str1.compareReadable(str2) == .orderedAscending))

      case (let num1 as IntegerValue, let num2 as IntegerValue):
        context.operands.push(.boolean(num1.value < num2.value))

      case (let num1 as RealValue, let num2 as RealValue):
        context.operands.push(.boolean(num1.value < num2.value))

      case (let num1 as NumericConvertible, let num2 as NumericConvertible):
        context.operands.push(.boolean(num1.real < num2.real))

      default:
        throw Error.typeCheck
      }
    }
  }

}
