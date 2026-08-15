//
//  NameValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object: ExpressibleByStringLiteral {

  /// Creates an instance.
  public init(stringLiteral value: StringLiteralType) {
    self.init(value: NameValue(value: value), kind: .literal)
  }

  /// Performs the ``name`` operation.
  public static func name(_ value: String, kind: ObjectKind) -> Self {
    Self(value: NameValue(value: value), kind: kind)
  }

  /// Performs the ``literalName`` operation.
  public static func literalName(_ value: String) -> Self {
    Self(value: NameValue(value: value), kind: .literal)
  }

  /// Performs the ``executableName`` operation.
  public static func executableName(_ value: String) -> Self {
    Self(value: NameValue(value: value), kind: .executable)
  }
}

/// A PostScript name value.
public struct NameValue: ObjectValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .name
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``value`` value.
  public let value: String

  /// Creates an instance.
  public init(value: String) {
    self.value = value
  }

  /// Performs the ``lookup`` operation.
  public func lookup(in context: isolated Context) throws -> Object {

    try context.dictionaries.object(forKey: .literalName(value))
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) throws {
    let object = try lookup(in: context)
    try object.execute(context: context, method: method)
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) -> Bool {
    switch other {
    case let otherName as NameValue:
      value == otherName.value
    case let otherString as StringValue:
      value == otherString.string
    default:
      false
    }
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(value)
  }

  /// A debug representation of this value.
  public var debugString: String { "\(value)" }
  /// The value's printable string representation, when available.
  public var valueString: String? { debugString }

  /// Returns the value's PostScript print representation.
  public func printString(kind: ObjectKind) -> String {
    kind == .executable ? debugString : "/\(debugString)"
  }

  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? { printString(kind: kind) }
}
