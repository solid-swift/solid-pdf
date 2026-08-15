//
//  ConversionOps.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation
import SolidCore

extension Operators {

  static let conversionOps: [OperatorValue] = [
    ConvertToInteger.instance,
    ConvertToReal.instance,
    ConvertToString.instance,
    ConvertToStringWithRadix.instance,
    ConvertToName.instance,
  ]

  /// Implements the PostScript `cvi` operator.
  public enum ConvertToInteger: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvi"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let op = try context.operands.pop()

      let integer =
        switch op.value {
        case let num as NumericConvertible:
          try num.integer

        case let str as StringValue:
          switch try Scanner.number(string: str.string) {
          case .integer(let int):
            int
          case .real(let real):
            try RealValue(validating: real, error: .undefinedResult).integer
          default:
            throw Error.syntaxError
          }

        default:
          throw Error.typeCheck
        }

      context.operands.push(.integer(integer))
    }
  }

  /// Implements the PostScript `cvr` operator.
  public enum ConvertToReal: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvr"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let op = try context.operands.pop()

      let real =
        switch op.value {
        case let num as NumericConvertible:
          num.real

        case let str as StringValue:
          switch try Scanner.number(string: str.string) {
          case .integer(let int):
            IntegerValue(value: int).real
          case .real(let real):
            real
          default:
            throw Error.syntaxError
          }

        default:
          throw Error.typeCheck
        }

      context.operands.push(try .real(real))
    }
  }

  /// Implements the PostScript `cvs` operator.
  public enum ConvertToString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvs"]

    /// The ``defaultValue`` value.
    public static let defaultValue = "--nostringval--".data(using: .isoLatin1).neverNil()

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (stringObj, anyObj) = try context.operands.pop2()
      let string = try stringObj.value(as: StringValue.self)

      let valueString = anyObj.valueString?.data(using: .isoLatin1) ?? Self.defaultValue
      guard string.count >= valueString.count else {
        throw Error.rangeCheck
      }

      try string.updateCharacters(valueString, startingAt: 0)
      let subRange = 0..<UInt(valueString.count)

      context.operands.push(try .string(sharing: string, subRange: subRange, kind: stringObj.kind))
    }
  }

  /// Implements the PostScript `cvrs` operator.
  public enum ConvertToStringWithRadix: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvrs"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (stringObj, radixObj, numObj) = try context.operands.pop3()
      let string = try stringObj.value(as: StringValue.self)
      let radix = try radixObj.value(as: IntegerValue.self).value
      let num = try numObj.value(as: NumericConvertible.self)

      guard radix >= 2 && radix <= 36 else {
        throw Error.rangeCheck
      }

      let valueString =
        if radix == 10 {
          num.valueString.neverNil()
            .data(using: .isoLatin1)
            .neverNil()
        } else {
          try String(UInt32(bitPattern: num.integer), radix: Int(radix), uppercase: true)
            .data(using: .isoLatin1)
            .neverNil()
        }

      guard string.count >= valueString.count else {
        throw Error.rangeCheck
      }

      try string.updateCharacters(valueString, startingAt: 0)
      let subRange = 0..<UInt(valueString.count)

      context.operands.push(try .string(sharing: string, subRange: subRange, kind: stringObj.kind))
    }
  }

  /// Implements the PostScript `cvn` operator.
  public enum ConvertToName: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvn"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let string: StringValue = try context.operands.popAs()

      context.operands.push(.literalName(string.string))
    }
  }
}
