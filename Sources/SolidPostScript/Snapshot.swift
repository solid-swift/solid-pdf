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

  private struct Backing: Sendable {
    let allocation: VMAllocation
    let vm: VM
    let bytes: Int
  }

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
    var graphicsState: GraphicsCanonicalState
    var graphicsStack: [GraphicsStackFrame]
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
    private var backings: [Backing] = []

    fileprivate init(
      packingMode: Context.PackingMode,
      allocationMode: VM,
      objectFormat: ObjectFormat,
      userParameters: UserParameterState,
      localResources: ResourceStore,
      graphicsState: GraphicsCanonicalState,
      graphicsStack: [GraphicsStackFrame],
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
      self.graphicsState = graphicsState
      self.graphicsStack = graphicsStack
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
        if !(composite is StringValue) && !(composite is FileValue) && !(composite is SaveValue) {
          backings.append(Backing(
            allocation: allocated.allocation,
            vm: allocated.vm,
            bytes: allocated.allocationFootprint
          ))
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
        backings: backings,
        packingMode: packingMode,
        allocationMode: allocationMode,
        objectFormat: objectFormat,
        userParameters: userParameters,
        localResources: localResources,
        graphicsState: graphicsState,
        graphicsStack: graphicsStack,
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
      graphicsState: context.graphicsState,
      graphicsStack: context.graphicsStack,
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
  private let globalResourceMutations = Mutex<[GlobalResourceMutation]>([])
  private let packingMode: Context.PackingMode
  private let allocationMode: VM
  private let objectFormat: ObjectFormat
  private let userParameters: UserParameterState
  private let localResources: ResourceStore
  private let graphicsState: GraphicsCanonicalState
  private let graphicsStack: [GraphicsStackFrame]
  private let saveDepth: Int
  private let localBoundary: VMGenerationBoundary
  private let globalBoundary: VMGenerationBoundary?
  private let accountingSpaces: [VMAllocationSpace]

  private init(
    retainedObjects: [Object],
    retainedStoredObjects: [VMStoredObject],
    operations: [RestoreOperation],
    backings: [Backing],
    packingMode: Context.PackingMode,
    allocationMode: VM,
    objectFormat: ObjectFormat,
    userParameters: UserParameterState,
    localResources: ResourceStore,
    graphicsState: GraphicsCanonicalState,
    graphicsStack: [GraphicsStackFrame],
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
    self.graphicsState = graphicsState
    self.graphicsStack = graphicsStack
    self.saveDepth = saveDepth
    self.localBoundary = localBoundary
    self.globalBoundary = globalBoundary
    self.accountingSpaces = if let globalBoundary {
      [localBoundary.space, globalBoundary.space]
    } else {
      [localBoundary.space]
    }

    for backing in backings {
      let space = switch backing.vm {
      case .local:
        localBoundary.space
      case .global:
        globalBoundary?.space
      }
      space?.registerSnapshot(self, allocation: backing.allocation, bytes: backing.bytes)
    }
  }

  deinit {
    releaseAccounting()
  }

  internal func restore(to context: isolated Context) async throws {

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

      let resourceMutations = globalResourceMutations.withLock { mutations in
        defer { mutations.removeAll() }
        return mutations
      }
      if !resourceMutations.isEmpty {
        try context.environment.rollbackGlobalResourceMutations(resourceMutations)
      }

      context.packingMode = packingMode
      context.allocationMode = allocationMode
      context.objectFormat = objectFormat
      context.userParameters = userParameters
      context.localResources = localResources
      try await context.transitionGraphicsState(to: graphicsState)
      context.graphicsStack = graphicsStack
      context.saveDepth = saveDepth
      context.applyUserParameterLimits()
      context.closeFiles(allocatedAfter: localBoundary, globalBoundary: globalBoundary)
      localBoundary.space.invalidateAllocations(after: localBoundary.generation)
      if let globalBoundary {
        globalBoundary.space.invalidateAllocations(after: globalBoundary.generation)
      }
      context.didRestore(self)
      state.withLock { $0 = .consumed }
      releaseAccounting()
    } catch {
      state.withLock { $0 = .invalidated }
      releaseAccounting()
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
    globalResourceMutations.withLock { $0.removeAll() }
    releaseAccounting()
  }

  var isReady: Bool {
    state.withLock { state in
      if case .ready = state { return true }
      return false
    }
  }

  private func releaseAccounting() {
    for space in accountingSpaces {
      space.releaseSnapshot(self)
    }
  }

  func recordGlobalResourceMutation(_ mutation: GlobalResourceMutation) {
    guard globalBoundary != nil else { return }
    guard state.withLock({ state in
      if case .ready = state { return true }
      return false
    }) else {
      return
    }
    globalResourceMutations.withLock { $0.append(mutation) }
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
