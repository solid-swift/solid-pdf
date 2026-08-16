//
//  TimeOps.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import SolidTempo

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
    public func execute(context: isolated Context) async throws {

      let elapsed = context.environment.monotonicInstantSource.instant.durationSinceEpoch
      context.operands.push(.integer(postScriptMilliseconds(elapsed)))
    }
  }

  /// Implements the PostScript `usertime` operator.
  public enum Usertime: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["usertime"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      context.operands.push(.integer(postScriptMilliseconds(context.userTime.elapsed)))
    }
  }

  private static func postScriptMilliseconds(_ duration: SolidTempo.Duration) -> Int32 {
    Int32(truncatingIfNeeded: duration[.totalMilliseconds])
  }

}
