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
  let vm: VM

  /// Creates an instance.
  public init(value: T, access: ObjectAccess, vm: VM) {
    self.state = Mutex((value, access))
    self.vm = vm
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
    return try state.withLock { try block(&$0) }
  }

  /// Performs the ``write`` operation.
  public func write<U: Sendable>(_ block: (inout State) throws -> U) throws -> U {
    return try state.withLock {
      try $0.access.check(.write)
      return try block(&$0)
    }
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    let capturedState = state.withLock { $0 }
    snapshot.save { [weak self] in
      self?.uncheckedWrite { $0 = capturedState }
    }
  }

}
