//
//  RandomOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
extension Operators {

  static let randomOps: [OperatorValue] = [
    Random.instance,
    GetRandomSeed.instance,
    SetRandomSeed.instance,
  ]

  /// Implements the PostScript `rand` operator.
  public enum Random: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["rand"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.operands.push(.integer(context.random.next()))
    }
  }

  /// Implements the PostScript `rrand` operator.
  public enum GetRandomSeed: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["rrand"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.operands.push(.integer(context.random.restorableState))
    }
  }

  /// Implements the PostScript `srand` operator.
  public enum SetRandomSeed: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["srand"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let arg: IntegerValue = try context.operands.popAs()
      context.random = Context.RandomGenerator(seed: arg.value)
    }
  }

}
