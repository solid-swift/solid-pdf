//
//  VMAllocation.swift
//

import Foundation
import Synchronization

struct VMGenerationBoundary: Sendable {
  let space: VMAllocationSpace
  let generation: UInt64
}

struct VMAllocationSpaces: Sendable {
  let local: VMAllocationSpace
  let global: VMAllocationSpace

  func space(for vm: VM) -> VMAllocationSpace {
    switch vm {
    case .local: local
    case .global: global
    }
  }
}

enum VMAllocationContext {
  @TaskLocal static var spaces: VMAllocationSpaces?

  static func allocation(in vm: VM, bytes: Int = 32) -> VMAllocation {
    guard let spaces else { return VMAllocation(vm: vm) }
    return spaces.space(for: vm).allocate(bytes: bytes)
  }
}

/// Serializes mutations to the managed PostScript object graph with collection.
enum VMGraph {
  private static let mutex = Mutex<Void>(())

  static func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
    try mutex.withLock { _ in try operation() }
  }
}

final class VMAllocation: Sendable {

  struct Membership: Sendable {
    let generation: UInt64
    var isValid: Bool
  }

  private struct MembershipRecord: @unchecked Sendable {
    let generation: UInt64
    var isValid: Bool
    let space: VMAllocationSpace
  }

  private struct State: @unchecked Sendable {
    var memberships: [UUID: MembershipRecord] = [:]
    var rootCount = 1
    var hasUnclaimedInitialRoot = true
    var edgeCount = 0
    var unspecifiedEdgeCount = 0
    var edgeSources: [ObjectIdentifier: (allocation: WeakVMAllocation, count: Int)] = [:]
    weak var owner: AnyObject?
    var children: (@Sendable () -> [VMAllocation])?
    var clear: (@Sendable () -> Void)?
  }

  let vm: VM
  private let state: Mutex<State>

  init(vm: VM) {
    self.vm = vm
    self.state = Mutex(State())
  }

  fileprivate init(vm: VM, space: VMAllocationSpace, generation: UInt64) {
    self.vm = vm
    self.state = Mutex(State(memberships: [
      space.id: MembershipRecord(generation: generation, isValid: true, space: space)
    ]))
  }

  var identity: ObjectIdentifier { ObjectIdentifier(self) }

  func membership(in space: VMAllocationSpace) -> Membership? {
    state.withLock { state in
      guard let membership = state.memberships[space.id] else { return nil }
      return Membership(generation: membership.generation, isValid: membership.isValid)
    }
  }

  var hasRoots: Bool { state.withLock { $0.rootCount > 0 } }

  var debugState: String {
    state.withLock { state in
      "roots=\(state.rootCount), edges=\(state.edgeCount), unspecified=\(state.unspecifiedEdgeCount), "
        + "memberships=\(state.memberships.values.map { "\($0.generation):\($0.isValid)" })"
    }
  }

  func hasExternalIncomingEdge(in space: VMAllocationSpace) -> Bool {
    let incoming = state.withLock { state in
      (
        state.unspecifiedEdgeCount,
        state.edgeSources.count,
        state.edgeSources.values.compactMap { $0.allocation.value }
      )
    }
    if incoming.0 > 0 { return true }
    if incoming.1 != incoming.2.count { return true }
    return incoming.2.contains { allocation in
      guard let membership = allocation.membership(in: space) else { return true }
      return !membership.isValid
    }
  }

  fileprivate func addMembership(in space: VMAllocationSpace, generation: UInt64) -> Bool {
    state.withLock { state in
      guard state.memberships[space.id] == nil else { return false }
      state.memberships[space.id] = MembershipRecord(generation: generation, isValid: true, space: space)
      return true
    }
  }

  fileprivate func refreshRetention(in space: VMAllocationSpace) {
    let owner = state.withLock { state in state.edgeCount > 0 ? state.owner : nil }
    if let owner { space.retain(owner, for: self) }
  }

  fileprivate func invalidate(in space: VMAllocationSpace, after boundary: UInt64) {
    state.withLock { state in
      guard var membership = state.memberships[space.id], membership.generation > boundary else { return }
      membership.isValid = false
      state.memberships[space.id] = membership
    }
  }

  func attach(
    owner: AnyObject,
    children: @escaping @Sendable () -> [VMAllocation] = { [] },
    clear: @escaping @Sendable () -> Void = {}
  ) {
    let spaces = state.withLock { state -> [VMAllocationSpace] in
      state.owner = owner
      state.children = children
      state.clear = clear
      guard state.edgeCount > 0 else { return [] }
      return state.memberships.values.map(\.space)
    }
    for space in spaces {
      space.retain(owner, for: self)
    }
  }

  fileprivate func addRoot() {
    state.withLock { state in
      if state.hasUnclaimedInitialRoot {
        state.hasUnclaimedInitialRoot = false
      } else {
        state.rootCount += 1
      }
    }
  }

  fileprivate func removeRoot() {
    state.withLock { state in
      precondition(state.rootCount > 0, "Unbalanced PostScript VM root lease")
      state.rootCount -= 1
    }
  }

  fileprivate func addEdge(to owner: AnyObject) -> Bool {
    let spaces = state.withLock { state -> [VMAllocationSpace] in
      state.edgeCount += 1
      state.unspecifiedEdgeCount += 1
      return state.memberships.values.map(\.space)
    }
    for space in spaces {
      space.retain(owner, for: self)
    }
    return !spaces.isEmpty
  }

  fileprivate func identifyEdgeSource(_ source: VMAllocation, replacing previous: VMAllocation?) {
    state.withLock { state in
      guard previous !== source else { return }
      if let previous {
        let identity = previous.identity
        guard var record = state.edgeSources[identity] else {
          preconditionFailure("Missing PostScript VM edge source")
        }
        record.count -= 1
        if record.count == 0 {
          state.edgeSources.removeValue(forKey: identity)
        } else {
          state.edgeSources[identity] = record
        }
      } else {
        precondition(state.unspecifiedEdgeCount > 0)
        state.unspecifiedEdgeCount -= 1
      }
      let identity = source.identity
      if var record = state.edgeSources[identity] {
        record.count += 1
        state.edgeSources[identity] = record
      } else {
        state.edgeSources[identity] = (WeakVMAllocation(source), 1)
      }
    }
  }

  fileprivate func refreshEdge(to owner: AnyObject) -> Bool {
    let spaces = state.withLock { $0.memberships.values.map(\.space) }
    for space in spaces {
      space.retain(owner, for: self)
    }
    return !spaces.isEmpty
  }

  fileprivate func removeEdge(from source: VMAllocation?) {
    let spaces = state.withLock { state -> [VMAllocationSpace] in
      precondition(state.edgeCount > 0, "Unbalanced PostScript VM edge lease")
      state.edgeCount -= 1
      if let source {
        let identity = source.identity
        if var record = state.edgeSources[identity] {
          record.count -= 1
          if record.count == 0 {
            state.edgeSources.removeValue(forKey: identity)
          } else {
            state.edgeSources[identity] = record
          }
        }
      } else {
        precondition(state.unspecifiedEdgeCount > 0)
        state.unspecifiedEdgeCount -= 1
      }
      guard state.edgeCount == 0 else { return [] }
      return state.memberships.values.map(\.space)
    }
    for space in spaces {
      space.releaseRetention(for: self)
    }
  }

  fileprivate func childAllocations() -> [VMAllocation] {
    let children = state.withLock { $0.children }
    return children?() ?? []
  }

  fileprivate func clearBacking() {
    let clear = state.withLock { $0.clear }
    clear?()
  }

  func updateFootprint(to bytes: Int, restoring: Bool = false) {
    let spaces = state.withLock { $0.memberships.values.map(\.space) }
    for space in spaces {
      space.adjustCharge(for: self, to: bytes, restoring: restoring)
    }
  }
}

/// A shared root lease retained by a language-visible composite handle.
final class VMRootLease: @unchecked Sendable {
  let allocation: VMAllocation
  private let owner: AnyObject

  init(allocation: VMAllocation, owner: AnyObject) {
    self.allocation = allocation
    self.owner = owner
    allocation.addRoot()
  }

  deinit {
    allocation.removeRoot()
  }
}

/// A logical object-graph edge that does not retain the target backing through ARC.
final class VMEdgeLease: @unchecked Sendable {
  let allocation: VMAllocation
  private weak var weakOwner: AnyObject?
  private var detachedOwner: AnyObject?
  private var source: VMAllocation?

  init(allocation: VMAllocation, owner: AnyObject) {
    self.allocation = allocation
    self.weakOwner = owner
    if !allocation.addEdge(to: owner) {
      // Detached public composites must remain usable until a context adopts their graph.
      self.detachedOwner = owner
    }
  }

  var owner: AnyObject? { weakOwner }

  func refresh() {
    guard let owner = weakOwner else { return }
    if allocation.refreshEdge(to: owner) {
      detachedOwner = nil
    }
  }


  func identifySource(_ source: VMAllocation) {
    let previous = self.source
    guard previous !== source else { return }
    self.source = source
    allocation.identifyEdgeSource(source, replacing: previous)
  }

  deinit {
    allocation.removeEdge(from: source)
  }
}

final class VMAllocationSpace: Sendable {

  private struct LedgerRecord: @unchecked Sendable {
    let allocation: WeakVMAllocation
    let generation: UInt64
    var chargedBytes: Int
  }

  private struct State: @unchecked Sendable {
    var generation: UInt64 = 0
    var ledger: [ObjectIdentifier: LedgerRecord] = [:]
    var retainedOwners: [ObjectIdentifier: AnyObject] = [:]
    var committedSinceCollection = 0
  }

  let id = UUID()
  let vm: VM
  private let state = Mutex(State())

  init(vm: VM) {
    self.vm = vm
  }

  func allocate(bytes: Int = 32) -> VMAllocation {
    precondition(bytes >= 0)
    return state.withLock { state in
      precondition(state.generation < .max, "PostScript VM allocation generation exhausted")
      state.generation += 1
      let allocation = VMAllocation(vm: vm, space: self, generation: state.generation)
      state.ledger[allocation.identity] = LedgerRecord(
        allocation: WeakVMAllocation(allocation),
        generation: state.generation,
        chargedBytes: bytes
      )
      state.committedSinceCollection = state.committedSinceCollection.saturatingAdd(bytes)
      return allocation
    }
  }

  func adopt(_ allocation: VMAllocation, chargedBytes: Int = 32) throws {
    precondition(allocation.vm == vm)
    if let membership = allocation.membership(in: self) {
      guard membership.isValid else { throw Error.invalidAccess }
      return
    }
    let generation = state.withLock { state -> UInt64 in
      precondition(state.generation < .max, "PostScript VM allocation generation exhausted")
      state.generation += 1
      return state.generation
    }
    guard allocation.addMembership(in: self, generation: generation) else { return }
    state.withLock { state in
      state.ledger[allocation.identity] = LedgerRecord(
        allocation: WeakVMAllocation(allocation),
        generation: generation,
        chargedBytes: chargedBytes
      )
      state.committedSinceCollection = state.committedSinceCollection.saturatingAdd(chargedBytes)
    }
    allocation.refreshRetention(in: self)
  }

  func boundary() -> VMGenerationBoundary {
    VMGenerationBoundary(space: self, generation: state.withLock { $0.generation })
  }

  var chargedBytes: Int {
    state.withLock { state in
      state.ledger.values.reduce(0) { $0.saturatingAdd($1.chargedBytes) }
    }
  }

  var bytesSinceCollection: Int { state.withLock { $0.committedSinceCollection } }

  func prepareForAllocation(
    bytes: Int,
    maximum: Int?,
    automaticCollection: Bool,
    threshold: Int,
    beforeFullCollection: () -> Void = {}
  ) -> Bool {
    precondition(bytes >= 0)
    precondition(threshold >= 0)

    if automaticCollection, bytesSinceCollection >= threshold {
      beforeFullCollection()
      collectCycles()
    }
    guard let maximum else { return true }
    if bytes <= maximum - min(chargedBytes, maximum) { return true }

    guard automaticCollection else { return false }

    pruneWeakGarbage()
    if bytes <= maximum - min(chargedBytes, maximum) { return true }

    beforeFullCollection()
    collectCycles()
    return bytes <= maximum - min(chargedBytes, maximum)
  }

  func adjustCharge(for allocation: VMAllocation, to bytes: Int, restoring: Bool = false) {
    precondition(bytes >= 0)
    state.withLock { state in
      guard var record = state.ledger[allocation.identity] else { return }
      if bytes > record.chargedBytes {
        state.committedSinceCollection = state.committedSinceCollection.saturatingAdd(bytes - record.chargedBytes)
      }
      record.chargedBytes = restoring ? bytes : max(record.chargedBytes, bytes)
      state.ledger[allocation.identity] = record
    }
  }

  func pruneWeakGarbage() {
    VMGraph.withLock {
      state.withLock { state in
        state.ledger = state.ledger.filter { $0.value.allocation.value != nil }
        state.retainedOwners = state.retainedOwners.filter { state.ledger[$0.key] != nil }
        state.committedSinceCollection = 0
      }
    }
  }

  func collectCycles(preservingAllocationsAfter boundary: UInt64? = nil) {
    let releasedOwners: [AnyObject] = VMGraph.withLock {
      let allocations = state.withLock { state -> [ObjectIdentifier: VMAllocation] in
        state.ledger = state.ledger.filter { $0.value.allocation.value != nil }
        return state.ledger.compactMapValues { $0.allocation.value }
      }

      var marked = Set<ObjectIdentifier>()
      var pending = allocations.values.filter { allocation in
        if allocation.hasRoots || allocation.hasExternalIncomingEdge(in: self) { return true }
        guard let boundary, let membership = allocation.membership(in: self) else { return false }
        return membership.generation > boundary
      }

      while let allocation = pending.popLast() {
        guard marked.insert(allocation.identity).inserted else { continue }
        pending.append(contentsOf: allocation.childAllocations())
      }

      let discarded = allocations.values.filter { !marked.contains($0.identity) }
      let releasedOwners = state.withLock { state -> [AnyObject] in
        var owners: [AnyObject] = []
        for allocation in discarded {
          if let owner = state.retainedOwners.removeValue(forKey: allocation.identity) {
            owners.append(owner)
          }
        }
        return owners
      }
      for allocation in discarded {
        allocation.clearBacking()
      }

      state.withLock { state in
        state.ledger = state.ledger.filter { $0.value.allocation.value != nil && marked.contains($0.key) }
        state.retainedOwners = state.retainedOwners.filter { marked.contains($0.key) }
        state.committedSinceCollection = 0
      }
      return releasedOwners
    }
    _ = releasedOwners
  }

  func invalidateAllocations(after boundary: UInt64) {
    let releasedOwners: [AnyObject] = VMGraph.withLock {
      let discarded = state.withLock { state -> (allocations: [VMAllocation], owners: [AnyObject]) in
        let identities = state.ledger.compactMap { identity, record in
          record.generation > boundary ? identity : nil
        }
        let discarded = identities.compactMap { state.ledger[$0]?.allocation.value }
        var owners: [AnyObject] = []
        for identity in identities {
          if let owner = state.retainedOwners.removeValue(forKey: identity) {
            owners.append(owner)
          }
          state.ledger.removeValue(forKey: identity)
        }
        return (discarded, owners)
      }
      for allocation in discarded.allocations {
        allocation.invalidate(in: self, after: boundary)
        allocation.clearBacking()
      }
      state.withLock { state in
        state.ledger = state.ledger.filter { $0.value.allocation.value != nil }
      }
      return discarded.owners
    }
    _ = releasedOwners
  }

  fileprivate func retain(_ owner: AnyObject, for allocation: VMAllocation) {
    state.withLock { state in
      guard state.ledger[allocation.identity] != nil else { return }
      state.retainedOwners[allocation.identity] = owner
    }
  }

  fileprivate func releaseRetention(for allocation: VMAllocation) {
    _ = state.withLock { $0.retainedOwners.removeValue(forKey: allocation.identity) }
  }
}

private final class WeakVMAllocation: @unchecked Sendable {
  weak var value: VMAllocation?

  init(_ value: VMAllocation) {
    self.value = value
  }
}

protocol VMAllocatedCompositeValue: CompositeValue {
  var allocation: VMAllocation { get }
  var allocationFootprint: Int { get }
  func refreshStoredEdges()
}

extension VMAllocatedCompositeValue {
  var allocationFootprint: Int { 32 }
  func refreshStoredEdges() {}
}

private extension Int {
  func saturatingAdd(_ other: Int) -> Int {
    let (value, overflow) = addingReportingOverflow(other)
    return overflow ? .max : value
  }
}
