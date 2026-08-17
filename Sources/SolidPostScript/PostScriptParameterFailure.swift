//
//  PostScriptParameterFailure.swift
//

import Foundation

/// A language error associated with an entry in a PostScript parameter dictionary.
public struct PostScriptParameterFailure: Swift.Error, Sendable {
  /// The language error raised by the invalid parameter.
  public let error: Error
  /// The parameter key associated with the error.
  public let key: Object
  /// The supplied value, or `nil` when a required entry was absent.
  public let value: Object?

  /// Creates a parameter-dictionary failure.
  public init(error: Error, key: Object, value: Object?) {
    self.error = error
    self.key = key
    self.value = value
  }
}

extension PostScriptParameterFailure {
  static func wrapping<Result>(
    key: Object,
    value: Object?,
    _ operation: () throws -> Result
  ) throws -> Result {
    do {
      return try operation()
    } catch let failure as PostScriptParameterFailure {
      throw failure
    } catch let error as Error {
      throw Self(error: error, key: key, value: value)
    }
  }
}
