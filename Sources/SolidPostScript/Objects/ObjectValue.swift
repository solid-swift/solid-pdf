//
//  ObjectValue.swift
//
//
//  Created by Kevin Wooten on 7/2/24.
//

import Foundation

/// A value that can be stored and executed as a PostScript object.
public protocol ObjectValue: CustomDebugStringConvertible, Sendable {

  static var objectType: ObjectType { get }

  static var defaultKind: ObjectKind { get }

  func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws

  func equals(_ other: any ObjectValue) throws -> Bool
  func hash(into hasher: inout Hasher)

  var valueString: String? { get }
  func tokenString(kind: ObjectKind) -> String?
  var debugString: String { get }
  func printString(kind: ObjectKind) -> String
}

extension ObjectValue {

  /// A debug representation of this value.
  public var debugDescription: String { debugString }

  /// The value's printable string representation, when available.
  public var valueString: String? { nil }
  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? { valueString }
  /// Returns the value's PostScript print representation.
  public func printString(kind: ObjectKind) -> String { debugString }

}
