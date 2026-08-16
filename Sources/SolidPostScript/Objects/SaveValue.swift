//
//  SaveValue.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation

/// A PostScript save value.
public struct SaveValue: CompositeValue, VMAllocatedCompositeValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .save
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``snapshot`` value.
  public let snapshot: Snapshot
  /// The access permitted for this value.
  public private(set) var access: ObjectAccess = Self.maxAccess
  /// Save objects are always allocated in local VM.
  public var vm: VM { .local }
  let allocation: VMAllocation

  init(snapshot: Snapshot) {
    self.snapshot = snapshot
    self.allocation = VMAllocationContext.allocation(in: .local)
  }

  /// Changes the access permitted for this value.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) throws -> Bool {
    guard let other = other as? Self else { return false }
    return snapshot === other.snapshot
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(snapshot))
  }

  /// A debug representation of this value.
  public var debugString: String {
    "save: \(snapshot.sequence)"
  }
}

extension SaveValue: SnapshotIdentifiableValue {
  var snapshotIdentity: ObjectIdentifier { allocation.identity }
}
