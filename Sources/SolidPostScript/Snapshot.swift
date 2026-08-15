//
//  Snapshot.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation
import Synchronization

/// A restorable snapshot of local PostScript virtual memory.
public final class Snapshot: Sendable {

  /// The type used to represent ``RestoreOperation``.
  public typealias RestoreOperation = @Sendable () throws -> Void

  private struct Payload: Sendable {
    let objects: Set<Object>
    let operations: [RestoreOperation]
  }

  private enum State: Sendable {
    case ready(Payload)
    case consumed
  }

  /// Collects objects and restore operations for a virtual-memory snapshot.
  public final class Builder {
    /// The ``packingMode`` value.
    public var packingMode: Context.PackingMode
    /// The ``allocationMode`` value.
    public var allocationMode: VM

    /// The ``objects`` value.
    public private(set) var objects: Set<Object> = []
    /// The ``operations`` value.
    public private(set) var operations: [RestoreOperation] = []

    fileprivate init(packingMode: Context.PackingMode, allocationMode: VM) {
      self.packingMode = packingMode
      self.allocationMode = allocationMode
    }

    /// Records restorable state in a snapshot builder.
    public func save(_ object: Object) {
      guard
        let composite = object.value as? CompositeValue,
        composite.vm == .local,
        objects.insert(object).inserted
      else {
        return
      }

      composite.save(to: self)
    }

    /// Records restorable state in a snapshot builder.
    public func save(_ block: @escaping RestoreOperation) {
      operations.append(block)
    }

    internal func build() -> Snapshot {
      return Snapshot(
        objects: objects,
        operations: operations,
        packingMode: packingMode,
        allocationMode: allocationMode
      )
    }
  }

  /// Performs the ``builder`` operation.
  public static func builder(for context: isolated Context) -> Builder {
    return Builder(
      packingMode: context.packingMode,
      allocationMode: context.allocationMode
    )
  }

  /// The ``timestamp`` value.
  public let timestamp: Date
  private let state: Mutex<State>
  private let packingMode: Context.PackingMode
  private let allocationMode: VM

  private init(
    objects: Set<Object>,
    operations: [RestoreOperation],
    packingMode: Context.PackingMode,
    allocationMode: VM
  ) {
    self.timestamp = Date.now
    self.state = Mutex(.ready(Payload(objects: objects, operations: operations)))
    self.packingMode = packingMode
    self.allocationMode = allocationMode
  }

  internal func restore(to context: isolated Context) throws {

    try check(context: context)

    let operations = try state.withLock { state in
      guard case .ready(let payload) = state, !payload.objects.isEmpty else {
        throw Error.invalidRestore
      }

      state = .consumed
      return payload.operations
    }

    for operation in operations {
      try operation()
    }

    context.packingMode = packingMode
    context.allocationMode = allocationMode
  }

  private func check(context: isolated Context) throws {

    var checked: Set<Object> = []

    func check(_ object: Object) throws {
      guard !checked.contains(object) else {
        return
      }
      checked.insert(object)

      switch object.value {
      case let save as SaveValue:
        if save.snapshot.timestamp > self.timestamp {
          throw Error.invalidRestore
        }

      case let dict as DictionaryValue:
        try dict.forEachUnchecked { key, value in
          try check(key)
          try check(value)
        }

      case let coll as CollectionValue:
        try coll.forEachUnchecked { value in
          try check(value)
        }

      default:
        break
      }
    }

    try context.operands.forEach(check)
    try context.dictionaries.forEach(check)
    try context.execution.map(\.source).forEach(check)
  }
}
