//
//  SaveValue.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation

/// A PostScript save value.
public struct SaveValue: ObjectValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .save
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``snapshot`` value.
  public let snapshot: Snapshot

  init(snapshot: Snapshot) {
    self.snapshot = snapshot
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) throws -> Bool {
    false
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
  }

  /// A debug representation of this value.
  public var debugString: String {
    "timestamp: \(snapshot.timestamp.formatted(.dateTime))"
  }
}
