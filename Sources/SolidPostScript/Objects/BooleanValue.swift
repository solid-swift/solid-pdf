//
//  BooleanValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object: ExpressibleByBooleanLiteral {

  /// Creates an instance.
  public init(booleanLiteral value: BooleanLiteralType) {
    self.init(value: BooleanValue(value: value))
  }

  /// Performs the ``boolean`` operation.
  public static func boolean(_ value: Bool) -> Self {
    .init(value: BooleanValue(value: value))
  }
}

/// A PostScript boolean value.
public struct BooleanValue: ObjectValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .boolean
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``value`` value.
  public let value: Bool

  /// Creates an instance.
  public init(value: Bool) {
    self.value = value
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    context.operands.push(.init(value: self, kind: kind))
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return value == other.value
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(value)
  }

  /// A debug representation of this value.
  public var debugString: String {
    "\(value)"
  }

  /// The value's printable string representation, when available.
  public var valueString: String? { debugString }
}
