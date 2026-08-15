//
//  TrigonometricOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Operators {

  static let trigonometricOps: [OperatorValue] = [
    Sine.instance,
    Cosine.instance,
    ArcTangent.instance,
  ]

  /// Implements the PostScript `sin` operator.
  public enum Sine: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["sin"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case let l as IntegerValue:
          .real(try sin(radians(l.real)))
        case let l as RealValue:
          .real(sin(radians(l.value)))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `cos` operator.
  public enum Cosine: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cos"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arg = try context.operands.pop()
      let result: Object =
        switch arg.value {
        case let l as IntegerValue:
          .real(try cos(radians(l.real)))
        case let l as RealValue:
          .real(cos(radians(l.value)))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }
  }

  /// Implements the PostScript `atan` operator.
  public enum ArcTangent: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["atan"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let args = try context.operands.pop(count: 2)
      let result: Object =
        switch (args[1].value, args[0].value) {
        case (let l as IntegerValue, let r as IntegerValue):
          .real(try degrees(atan2(l.real, r.real)))
        case (let l as RealValue, let r as RealValue):
          .real(degrees(atan2(l.value, r.value)))
        case (let l as NumericConvertible, let r as NumericConvertible):
          .real(try degrees(atan2(l.real, r.real)))
        default:
          throw Error.typeCheck
        }
      context.operands.push(result)
    }

  }

  private static let radiansToDegreesCoeff = 180.0 / .pi
  private static let degreesToRadiansCoeff = .pi / 180.0

  private static func degrees(_ radians: Double) -> Double {
    ((radians * radiansToDegreesCoeff) + 360.0).truncatingRemainder(dividingBy: 360.0)
  }

  private static func radians(_ degrees: Double) -> Double {
    degrees * degreesToRadiansCoeff
  }

}
