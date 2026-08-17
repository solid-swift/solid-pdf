//
//  Shared.swift
//  TPPackages
//
//  Created by Kevin Wooten on 12/24/24.
//

import Foundation
import Synchronization

/// Thread-safe shared storage for composite PostScript values.
public final class CompositeShared<T: Sendable>: Sendable {

  /// The type used to represent ``State``.
  public typealias State = (value: T, access: ObjectAccess)

  private let state: Mutex<State>
  private let revision = Mutex<UInt64>(0)
  private let footprint: @Sendable (T) -> Int
  private let snapshotCopy: @Sendable (T) -> T
  private let storedObjects: @Sendable (T) -> [VMStoredObject]
  private let identifyEdges: @Sendable (T, VMAllocation) -> Void
  let vm: VM
  let allocation: VMAllocation

  /// Creates an instance.
  public convenience init(value: T, access: ObjectAccess, vm: VM) {
    self.init(value: value, access: access, vm: vm, chargedBytes: 32, footprint: { _ in 32 })
  }

  init(
    value: T,
    access: ObjectAccess,
    vm: VM,
    chargedBytes: Int,
    footprint: @escaping @Sendable (T) -> Int,
    children: @escaping @Sendable (T) -> [VMAllocation] = { _ in [] },
    snapshotCopy: @escaping @Sendable (T) -> T = { $0 },
    storedObjects: @escaping @Sendable (T) -> [VMStoredObject] = { _ in [] },
    identifyEdges: @escaping @Sendable (T, VMAllocation) -> Void = { _, _ in },
    clear: @escaping @Sendable (inout T) -> Void = { _ in }
  ) {
    self.state = Mutex((value, access))
    self.vm = vm
    self.footprint = footprint
    self.snapshotCopy = snapshotCopy
    self.storedObjects = storedObjects
    self.identifyEdges = identifyEdges
    self.allocation = VMAllocationContext.allocation(in: vm, bytes: chargedBytes)
    self.allocation.attach(
      owner: self,
      children: { [weak self] in
        self?.state.withLock { children($0.value) } ?? []
      },
      clear: { [weak self] in
        self?.state.withLock { clear(&$0.value) }
      }
    )
  }

  /// Performs the ``uncheckedRead`` operation.
  public func uncheckedRead<U: Sendable>(_ block: (State) throws -> U) rethrows -> U {
    return try state.withLock { try block($0) }
  }

  /// Performs the ``read`` operation.
  public func read<U: Sendable>(_ block: (State) throws -> U) throws -> U {
    return try state.withLock {
      try $0.access.check(.read)
      return try block($0)
    }
  }

  /// Performs the ``uncheckedWrite`` operation.
  public func uncheckedWrite<U: Sendable>(_ block: (inout State) throws -> U) rethrows -> U {
    return try VMGraph.withLock {
      try state.withLock {
        defer { revision.withLock { $0 &+= 1 } }
        return try block(&$0)
      }
    }
  }

  /// Performs the ``write`` operation.
  public func write<U: Sendable>(_ block: (inout State) throws -> U) throws -> U {
    try state.withLock { try $0.access.check(.write) }
    try allocation.prepareSnapshotMutation()
    return try VMGraph.withLock {
      try state.withLock {
        try $0.access.check(.write)
        defer { revision.withLock { $0 &+= 1 } }
        return try block(&$0)
      }
    }
  }

  // Captures derived state and its revision while holding the same storage lock used by writers.
  func versionedRead<U: Sendable>(_ block: (State) throws -> U) rethrows -> (revision: UInt64, value: U) {
    try state.withLock {
      let value = try block($0)
      return (revision.withLock { $0 }, value)
    }
  }

  // Commits only when no writer has changed the state since a versioned read.
  func write(ifRevision expectedRevision: UInt64, _ block: (inout State) throws -> Void) throws -> Bool {
    try state.withLock { try $0.access.check(.write) }
    try allocation.prepareSnapshotMutation()
    return try VMGraph.withLock {
      try state.withLock {
        guard revision.withLock({ $0 }) == expectedRevision else { return false }
        try $0.access.check(.write)
        defer { revision.withLock { $0 &+= 1 } }
        try block(&$0)
        return true
      }
    }
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    let capturedState: State = state.withLock { (snapshotCopy($0.value), $0.access) }
    snapshot.retainStoredObjects(storedObjects(capturedState.value))
    snapshot.save { [weak self] in
      guard let self else { return }
      self.uncheckedWrite {
        $0 = capturedState
        self.identifyEdges($0.value, self.allocation)
      }
      self.allocation.updateFootprint(to: self.footprint(capturedState.value), restoring: true)
    }
  }

}
