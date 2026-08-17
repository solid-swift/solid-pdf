//
//  DeferOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Operators {

  /// A legacy representation of the former PostScript `{` operator.
  @available(*, deprecated, message: "Procedure literals are constructed by the scanner")
  public enum Defer: OperatorValue {
    case instance

    /// The legacy system-dictionary names for this value.
    public static let systemDictionaryNames: [Object] = ["{"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      throw Error.syntaxError
    }
  }

}
