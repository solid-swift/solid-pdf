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

  static func allocation(in vm: VM) -> VMAllocation {
    guard let spaces else { return VMAllocation(vm: vm) }
    return spaces.space(for: vm).allocate()
  }
}

final class VMAllocation: Sendable {

  struct Membership: Sendable {
    let generation: UInt64
    var isValid: Bool
  }

  let vm: VM
  private let memberships: Mutex<[UUID: Membership]>

  init(vm: VM) {
    self.vm = vm
    self.memberships = Mutex([:])
  }

  fileprivate init(vm: VM, spaceID: UUID, generation: UInt64) {
    self.vm = vm
    self.memberships = Mutex([
      spaceID: Membership(generation: generation, isValid: true)
    ])
  }

  var identity: ObjectIdentifier { ObjectIdentifier(self) }

  func membership(in space: VMAllocationSpace) -> Membership? {
    memberships.withLock { $0[space.id] }
  }

  fileprivate func addMembership(in space: VMAllocationSpace, generation: UInt64) -> Bool {
    memberships.withLock { memberships in
      guard memberships[space.id] == nil else { return false }
      memberships[space.id] = Membership(generation: generation, isValid: true)
      return true
    }
  }

  fileprivate func invalidate(in space: VMAllocationSpace, after boundary: UInt64) {
    memberships.withLock { memberships in
      guard var membership = memberships[space.id], membership.generation > boundary else { return }
      membership.isValid = false
      memberships[space.id] = membership
    }
  }
}

final class VMAllocationSpace: Sendable {

  private struct State: Sendable {
    var generation: UInt64 = 0
    var allocations: [WeakVMAllocation] = []
  }

  let id = UUID()
  let vm: VM
  private let state = Mutex(State())

  init(vm: VM) {
    self.vm = vm
  }

  func allocate() -> VMAllocation {
    state.withLock { state in
      precondition(state.generation < .max, "PostScript VM allocation generation exhausted")
      state.generation += 1
      let allocation = VMAllocation(vm: vm, spaceID: id, generation: state.generation)
      state.allocations.append(WeakVMAllocation(allocation))
      return allocation
    }
  }

  func adopt(_ allocation: VMAllocation) throws {
    precondition(allocation.vm == vm)
    try state.withLock { state in
      if let membership = allocation.membership(in: self) {
        guard membership.isValid else { throw Error.invalidAccess }
        return
      }
      precondition(state.generation < .max, "PostScript VM allocation generation exhausted")
      state.generation += 1
      guard allocation.addMembership(in: self, generation: state.generation) else { return }
      state.allocations.append(WeakVMAllocation(allocation))
    }
  }

  func boundary() -> VMGenerationBoundary {
    VMGenerationBoundary(space: self, generation: state.withLock { $0.generation })
  }

  func invalidateAllocations(after boundary: UInt64) {
    let allocations = state.withLock { state -> [VMAllocation] in
      state.allocations.removeAll { $0.value == nil }
      return state.allocations.compactMap(\.value)
    }
    for allocation in allocations {
      allocation.invalidate(in: self, after: boundary)
    }
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
}
