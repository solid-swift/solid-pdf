//
//  RealValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object {
  /// Performs the ``real`` operation.
  public static func real(_ value: Double) -> Self {
    .init(value: RealValue(value: value))
  }
}

/// A PostScript real value.
public struct RealValue: ObjectValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .real
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``value`` value.
  public let value: Double

  /// Creates an instance.
  public init(value: Double) {
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
    return try value == other.real
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(value)
  }

  /// A debug representation of this value.
  public var debugString: String {
    "\(value.formatted(.number.precision(.fractionLength(3))))"
  }

  /// The value's printable string representation, when available.
  public var valueString: String? { String(value) }
}
