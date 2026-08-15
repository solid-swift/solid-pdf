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
      guard let angle = arg.value as? NumericConvertible else {
        throw Error.typeCheck
      }
      let result: Object = try .real(sin(radians(angle.real)))
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
      guard let angle = arg.value as? NumericConvertible else {
        throw Error.typeCheck
      }
      let result: Object = try .real(cos(radians(angle.real)))
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
      guard let numerator = args[1].value as? NumericConvertible,
        let denominator = args[0].value as? NumericConvertible
      else {
        throw Error.typeCheck
      }
      guard numerator.real != 0 || denominator.real != 0 else {
        throw Error.undefinedResult
      }
      let result: Object = try .real(degrees(atan2(numerator.real, denominator.real)))
      context.operands.push(result)
    }

  }

  private static let radiansToDegreesCoeff = 180.0 / .pi
  private static let degreesToRadiansCoeff = .pi / 180.0

  private static func degrees(_ radians: Double) -> Double {
    ((radians * radiansToDegreesCoeff) + 360.0).truncatingRemainder(dividingBy: 360.0)
  }

  private static func radians(_ degrees: Double) -> Double {
    degrees.truncatingRemainder(dividingBy: 360.0) * degreesToRadiansCoeff
  }

}
