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

  enum Scope: Sendable {
    case local
    case job
  }

  /// The type used to represent ``RestoreOperation``.
  public typealias RestoreOperation = @Sendable () throws -> Void

  private struct Payload: Sendable {
    let retainedObjects: [Object]
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
    var objectFormat: ObjectFormat
    var userParameters: UserParameterState
    var localResources: ResourceStore
    let saveDepth: Int
    let fileGeneration: Int
    private let scope: Scope

    /// The ``objects`` value.
    public private(set) var objects: Set<Object> = []
    /// The ``operations`` value.
    public private(set) var operations: [RestoreOperation] = []
    private var savedCompositeIdentities: Set<ObjectIdentifier> = []
    private var retainedObjects: [Object] = []

    fileprivate init(
      packingMode: Context.PackingMode,
      allocationMode: VM,
      objectFormat: ObjectFormat,
      userParameters: UserParameterState,
      localResources: ResourceStore,
      saveDepth: Int,
      fileGeneration: Int,
      scope: Scope
    ) {
      self.packingMode = packingMode
      self.allocationMode = allocationMode
      self.objectFormat = objectFormat
      self.userParameters = userParameters
      self.localResources = localResources
      self.saveDepth = saveDepth
      self.fileGeneration = fileGeneration
      self.scope = scope
    }

    /// Records restorable state in a snapshot builder.
    public func save(_ object: Object) {
      guard let composite = object.value as? CompositeValue,
        composite.vm == .local || scope == .job
      else {
        return
      }

      if let identifiable = composite as? SnapshotIdentifiableValue {
        guard savedCompositeIdentities.insert(identifiable.snapshotIdentity).inserted else {
          return
        }
      }

      retainedObjects.append(object)
      if !(composite is StringValue) && !(composite is PackedArrayValue) {
        objects.insert(object)
      }
      composite.save(to: self)
    }

    /// Records restorable state in a snapshot builder.
    public func save(_ block: @escaping RestoreOperation) {
      operations.append(block)
    }

    internal func build() -> Snapshot {
      return Snapshot(
        retainedObjects: retainedObjects,
        operations: operations,
        packingMode: packingMode,
        allocationMode: allocationMode,
        objectFormat: objectFormat,
        userParameters: userParameters,
        localResources: localResources,
        saveDepth: saveDepth,
        fileGeneration: fileGeneration
      )
    }
  }

  /// Performs the ``builder`` operation.
  public static func builder(for context: isolated Context) -> Builder {
    builder(for: context, fileGeneration: 0, scope: .local)
  }

  static func builder(for context: isolated Context, fileGeneration: Int, scope: Scope = .local) -> Builder {
    return Builder(
      packingMode: context.packingMode,
      allocationMode: context.allocationMode,
      objectFormat: context.objectFormat,
      userParameters: context.userParameters,
      localResources: context.localResources,
      saveDepth: context.saveDepth,
      fileGeneration: fileGeneration,
      scope: scope
    )
  }

  /// The ``timestamp`` value.
  public let timestamp: Date
  private let state: Mutex<State>
  private let packingMode: Context.PackingMode
  private let allocationMode: VM
  private let objectFormat: ObjectFormat
  private let userParameters: UserParameterState
  private let localResources: ResourceStore
  private let saveDepth: Int
  private let fileGeneration: Int

  private init(
    retainedObjects: [Object],
    operations: [RestoreOperation],
    packingMode: Context.PackingMode,
    allocationMode: VM,
    objectFormat: ObjectFormat,
    userParameters: UserParameterState,
    localResources: ResourceStore,
    saveDepth: Int,
    fileGeneration: Int
  ) {
    self.timestamp = Date.now
    self.state = Mutex(.ready(Payload(retainedObjects: retainedObjects, operations: operations)))
    self.packingMode = packingMode
    self.allocationMode = allocationMode
    self.objectFormat = objectFormat
    self.userParameters = userParameters
    self.localResources = localResources
    self.saveDepth = saveDepth
    self.fileGeneration = fileGeneration
  }

  internal func restore(to context: isolated Context) throws {

    try check(context: context)

    let operations = try state.withLock { state in
      guard case .ready(let payload) = state, !payload.retainedObjects.isEmpty else {
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
    context.objectFormat = objectFormat
    context.userParameters = userParameters
    context.localResources = localResources
    context.saveDepth = saveDepth
    context.applyUserParameterLimits()
    context.closeFiles(openedAfter: fileGeneration)
  }

  private func check(context: isolated Context) throws {

    var checkedCompositeIdentities: Set<ObjectIdentifier> = []

    func check(_ object: Object) throws {
      if let identifiable = object.value as? SnapshotIdentifiableValue {
        guard checkedCompositeIdentities.insert(identifiable.snapshotIdentity).inserted else {
          return
        }
      }

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

final class WeakFile: @unchecked Sendable {

  weak var value: (any File)?

  init(_ value: any File) {
    self.value = value
  }

}
