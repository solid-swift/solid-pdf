//
//  NullValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object: ExpressibleByNilLiteral {

  /// Creates an instance.
  public init(nilLiteral: ()) {
    self.init(value: NullValue.instance)
  }

  /// The ``null`` value.
  public static var null: Self { Self(value: NullValue.instance) }
}

/// A PostScript null value.
public enum NullValue: ObjectValue {
  case instance

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .null
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) -> Bool {
    other is Self
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
  }

  /// A debug representation of this value.
  public var debugString: String { "" }
  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? { "null" }
}
