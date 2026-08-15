//
//  IntegerValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object: ExpressibleByIntegerLiteral {

  /// Creates an instance.
  public init(integerLiteral value: IntegerLiteralType) {
    self.init(value: IntegerValue(value: value))
  }

  /// Performs the ``integer`` operation.
  public static func integer(_ value: Int) -> Self {
    Self(value: IntegerValue(value: value))
  }
}

/// An PostScript integer value.
public struct IntegerValue: ObjectValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .integer
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``value`` value.
  public let value: Int

  /// Creates an instance.
  public init(value: Int) {
    self.value = value
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) throws {
    context.operands.push(.init(value: self, kind: kind))
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) throws -> Bool {
    guard let other = other as? NumericConvertible else {
      return false
    }
    return try value == other.integer
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(value)
  }

  /// A debug representation of this value.
  public var debugString: String { "\(value)" }
  /// The value's printable string representation, when available.
  public var valueString: String? { debugString }
}
