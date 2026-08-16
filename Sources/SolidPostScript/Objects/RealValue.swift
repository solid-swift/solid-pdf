//
//  RealValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object {
  /// Creates a real object when `value` is finite.
  public static func real(finite value: Double) -> Self? {
    RealValue(finite: value).map { .init(value: $0) }
  }

  static func real(
    _ value: Double,
    underflowed: Bool = false,
    error: Error = .undefinedResult
  ) throws -> Self {
    guard !underflowed else {
      throw error
    }
    return try .init(value: RealValue(validating: value, error: error))
  }
}

/// A PostScript real value.
public struct RealValue: ObjectValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .real
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The finite binary64 PostScript real value.
  public let value: Double

  /// Creates an instance when `value` is finite.
  public init?(finite value: Double) {
    guard value.isFinite else {
      return nil
    }
    self.value = value
  }

  init(validating value: Double, error: Error) throws {
    guard value.isFinite else {
      throw error
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
    return value == other.real
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
