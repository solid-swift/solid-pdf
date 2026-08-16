//
//  OperatorValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

/// A PostScript operator implementation.
public protocol OperatorValue: ObjectValue {
  static var systemDictionaryNames: [Object] { get }

  var systemDictionaryNames: [Object] { get }

  func execute(context: isolated Context) async throws
}

extension OperatorValue {

  /// The PostScript object type represented by this value.
  public static var objectType: ObjectType { .operator }
  /// The default execution kind for this value.
  public static var defaultKind: ObjectKind { .executable }

  /// The names that register this operator in the system dictionary.
  public var systemDictionaryNames: [Object] { Self.systemDictionaryNames }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) -> Bool {
    return other is Self
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    try await execute(context: context)
  }

  /// A debug representation of this value.
  public var debugString: String { Self.systemDictionaryNames[0].valueString.neverNil() }
  /// The value's printable string representation, when available.
  public var valueString: String? { debugString }
}
