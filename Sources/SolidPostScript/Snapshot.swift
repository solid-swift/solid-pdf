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
    let retainedObjects: [VMStoredObject]
    let operations: [RestoreOperation]
  }

  private enum State: Sendable {
    case ready(Payload)
    case restoring
    case consumed
    case invalidated
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
    let sequence: UInt64
    let localBoundary: VMGenerationBoundary
    let globalBoundary: VMGenerationBoundary?
    private let scope: Scope

    /// The ``objects`` value.
    public private(set) var objects: Set<Object> = []
    /// The ``operations`` value.
    public private(set) var operations: [RestoreOperation] = []
    private var savedCompositeIdentities: Set<ObjectIdentifier> = []
    private var retainedObjects: [Object] = []
    private var retainedStoredObjects: [VMStoredObject] = []

    fileprivate init(
      packingMode: Context.PackingMode,
      allocationMode: VM,
      objectFormat: ObjectFormat,
      userParameters: UserParameterState,
      localResources: ResourceStore,
      saveDepth: Int,
      sequence: UInt64,
      localBoundary: VMGenerationBoundary,
      globalBoundary: VMGenerationBoundary?,
      scope: Scope
    ) {
      self.packingMode = packingMode
      self.allocationMode = allocationMode
      self.objectFormat = objectFormat
      self.userParameters = userParameters
      self.localResources = localResources
      self.saveDepth = saveDepth
      self.sequence = sequence
      self.localBoundary = localBoundary
      self.globalBoundary = globalBoundary
      self.scope = scope
    }

    /// Records restorable state in a snapshot builder.
    public func save(_ object: Object) {
      guard let composite = object.value as? CompositeValue,
        composite.vm == .local || scope == .job
      else {
        return
      }

      if let allocated = composite as? VMAllocatedCompositeValue {
        guard savedCompositeIdentities.insert(allocated.allocation.identity).inserted else {
          return
        }
      } else if let identifiable = composite as? SnapshotIdentifiableValue {
        guard savedCompositeIdentities.insert(identifiable.snapshotIdentity).inserted else { return }
      }

      retainedObjects.append(object)
      if !(composite is StringValue) {
        objects.insert(object)
      }
      composite.save(to: self)
    }

    /// Records restorable state in a snapshot builder.
    public func save(_ block: @escaping RestoreOperation) {
      operations.append(block)
    }

    func retainStoredObjects(_ objects: [VMStoredObject]) {
      retainedStoredObjects.append(contentsOf: objects)
    }

    internal func build() -> Snapshot {
      return Snapshot(
        retainedObjects: retainedObjects,
        retainedStoredObjects: retainedStoredObjects,
        operations: operations,
        packingMode: packingMode,
        allocationMode: allocationMode,
        objectFormat: objectFormat,
        userParameters: userParameters,
        localResources: localResources,
        saveDepth: saveDepth,
        sequence: sequence,
        localBoundary: localBoundary,
        globalBoundary: globalBoundary
      )
    }
  }

  /// Performs the ``builder`` operation.
  public static func builder(for context: isolated Context) -> Builder {
    builder(for: context, scope: .local)
  }

  static func builder(for context: isolated Context, scope: Scope = .local) -> Builder {
    return Builder(
      packingMode: context.packingMode,
      allocationMode: context.allocationMode,
      objectFormat: context.objectFormat,
      userParameters: context.userParameters,
      localResources: context.localResources,
      saveDepth: context.saveDepth,
      sequence: context.takeSnapshotSequence(),
      localBoundary: context.localVMAllocationSpace.boundary(),
      globalBoundary: scope == .job ? context.environment.globalVMAllocationSpace.boundary() : nil,
      scope: scope
    )
  }

  /// The creation timestamp retained for diagnostics; restore ordering uses VM generations.
  public let timestamp: Date
  let sequence: UInt64
  private let state: Mutex<State>
  private let packingMode: Context.PackingMode
  private let allocationMode: VM
  private let objectFormat: ObjectFormat
  private let userParameters: UserParameterState
  private let localResources: ResourceStore
  private let saveDepth: Int
  private let localBoundary: VMGenerationBoundary
  private let globalBoundary: VMGenerationBoundary?

  private init(
    retainedObjects: [Object],
    retainedStoredObjects: [VMStoredObject],
    operations: [RestoreOperation],
    packingMode: Context.PackingMode,
    allocationMode: VM,
    objectFormat: ObjectFormat,
    userParameters: UserParameterState,
    localResources: ResourceStore,
    saveDepth: Int,
    sequence: UInt64,
    localBoundary: VMGenerationBoundary,
    globalBoundary: VMGenerationBoundary?
  ) {
    self.timestamp = Date.now
    self.sequence = sequence
    self.state = Mutex(.ready(Payload(
      retainedObjects: retainedObjects.map(VMStoredObject.init) + retainedStoredObjects,
      operations: operations
    )))
    self.packingMode = packingMode
    self.allocationMode = allocationMode
    self.objectFormat = objectFormat
    self.userParameters = userParameters
    self.localResources = localResources
    self.saveDepth = saveDepth
    self.localBoundary = localBoundary
    self.globalBoundary = globalBoundary
  }

  internal func restore(to context: isolated Context) throws {

    try check(context: context)

    let operations = try state.withLock { state in
      guard case .ready(let payload) = state else {
        throw Error.invalidRestore
      }

      state = .restoring
      return payload.operations
    }

    do {
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
      context.closeFiles(allocatedAfter: localBoundary, globalBoundary: globalBoundary)
      localBoundary.space.invalidateAllocations(after: localBoundary.generation)
      if let globalBoundary {
        globalBoundary.space.invalidateAllocations(after: globalBoundary.generation)
      }
      context.didRestore(self)
      state.withLock { $0 = .consumed }
    } catch {
      state.withLock { $0 = .invalidated }
      throw error
    }
  }

  private func check(context: isolated Context) throws {
    guard localBoundary.space === context.localVMAllocationSpace else {
      throw Error.invalidRestore
    }

    func check(_ object: Object) throws {
      guard let composite = object.value as? VMAllocatedCompositeValue else { return }
      let boundary = switch composite.vm {
      case .local:
        localBoundary
      case .global:
        globalBoundary
      }
      guard let boundary else { return }
      guard let membership = composite.allocation.membership(in: boundary.space), membership.isValid else {
        throw Error.invalidRestore
      }
      if membership.generation > boundary.generation {
        throw Error.invalidRestore
      }
    }

    try context.operands.forEach(check)
    try context.dictionaries.forEach(check)
    try context.execution.map(\.source).forEach(check)
  }

  func invalidate() {
    state.withLock { state in
      if case .ready = state {
        state = .invalidated
      }
    }
  }

  func retainedAllocations() -> [VMAllocation] {
    state.withLock { state in
      guard case .ready(let payload) = state else { return [] }
      return payload.retainedObjects.compactMap(\.allocation)
    }
  }

  func identifyRetainedEdges(source: VMAllocation) {
    state.withLock { state in
      guard case .ready(let payload) = state else { return }
      payload.retainedObjects.identifyVMEdgeSources(source)
    }
  }
}

final class WeakFile: @unchecked Sendable {

  weak var value: (any File)?

  init(_ value: any File) {
    self.value = value
  }

}
