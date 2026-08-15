//
//  MarkValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Object {
  /// The ``mark`` value.
  public static var mark: Self { Self(value: MarkValue.instance) }
}

/// A PostScript mark value.
public enum MarkValue: ObjectValue {
  case instance

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .mark
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) throws {
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
  public func tokenString(kind: ObjectKind) -> String? { "mark" }
}
