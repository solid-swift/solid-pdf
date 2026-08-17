//
//  IntegerValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object: ExpressibleByIntegerLiteral {

  public typealias IntegerLiteralType = Int32

  /// Creates an instance.
  public init(integerLiteral value: IntegerLiteralType) {
    self.init(value: IntegerValue(value: value))
  }

  /// Performs the ``integer`` operation.
  public static func integer(_ value: Int32) -> Self {
    Self(value: IntegerValue(value: value))
  }

  /// Creates an integer object when `value` is representable by PostScript.
  public static func integer<T: BinaryInteger>(exactly value: T) -> Self? {
    IntegerValue(exactly: value).map { Self(value: $0) }
  }
}

/// An PostScript integer value.
public struct IntegerValue: ObjectValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .integer
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The signed 32-bit PostScript integer value.
  public let value: Int32

  /// Creates an instance.
  public init(value: Int32) {
    self.value = value
  }

  /// Creates an instance when `value` is representable by PostScript.
  public init?<T: BinaryInteger>(exactly value: T) {
    guard let value = Int32(exactly: value) else {
      return nil
    }
    self.value = value
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    context.operands.push(.init(value: self, kind: kind))
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) throws -> Bool {
    guard let other = other as? NumericConvertible else {
      return false
    }
    return real == other.real
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
