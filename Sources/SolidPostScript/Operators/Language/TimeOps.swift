//
//  TimeOps.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation

extension Operators {

  static let timeOps: [OperatorValue] = [
    Realtime.instance,
    Usertime.instance,
  ]

  /// Implements the PostScript `realtime` operator.
  public enum Realtime: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["realtime"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let time = Int64(Date.timeIntervalSinceReferenceDate * 1000)

      context.operands.push(.integer(Int32(truncatingIfNeeded: time)))
    }
  }

  /// Implements the PostScript `usertime` operator.
  public enum Usertime: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["usertime"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let time = Int64((Date.timeIntervalSinceReferenceDate - context.start) * 1000)

      context.operands.push(.integer(Int32(truncatingIfNeeded: time)))
    }
  }

}
