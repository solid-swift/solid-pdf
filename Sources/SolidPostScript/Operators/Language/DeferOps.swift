//
//  DeferOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Operators {

  static let deferOps: [OperatorValue] = [
    Defer.instance
  ]

  /// Implements the PostScript `{` operator.
  public enum Defer: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["{"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      context.operands.push(.mark)
      context.executionModes.push(.deferred)
    }
  }

}
