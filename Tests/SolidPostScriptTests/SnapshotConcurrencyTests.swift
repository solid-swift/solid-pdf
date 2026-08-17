//
//  SnapshotConcurrencyTests.swift
//

import Foundation
import Testing

@testable import SolidPostScript

@Suite
struct SnapshotConcurrencyTests {

  @Test func restoresNestedLocalContainers() async throws {
    let nested = try DictionaryValue(value: ["value": 1], access: .unlimited, vm: .local)
    let array = try ArrayValue(
      elements: [Object(value: nested), 2],
      access: .unlimited,
      vm: .local
    )
    let context = Context()
    let snapshot = await context.snapshot(of: Object(value: array))

    try nested.updateObject(10, forKey: "value")
    try array.updateObject(20, at: 1)
    try await snapshot.restore(to: context)

    #expect(try nested.objectValue(forKey: "value", as: IntegerValue.self).value == 1)
    let restoredValue = try array.object(at: 1).value(as: IntegerValue.self).value
    #expect(restoredValue == 2, "Expected restored array value 2, got \(restoredValue)")
  }

  @Test func intervalSnapshotRestoresTheCompleteSharedBacking() async throws {
    let array = try ArrayValue(elements: [1, 2, 3], access: .unlimited, vm: .local)
    let interval = try ArrayValue(sharing: array, subRange: 1..<2)
    let context = Context()
    let snapshot = await context.snapshot(of: Object(value: interval))

    try array.updateObject(10, at: 0)
    try array.updateObject(20, at: 1)
    try array.updateObject(30, at: 2)
    try await snapshot.restore(to: context)

    let restored = try (0..<array.count).map { try array.object(at: $0).value(as: IntegerValue.self).value }
    #expect(restored == [1, 2, 3])
  }

  @Test func adoptingAnIntervalAdoptsAllocationsRetainedOutsideItsView() async throws {
    let nested = try ArrayValue(elements: [1], access: .unlimited, vm: .local)
    let array = try ArrayValue(elements: [Object(value: nested), 2], access: .unlimited, vm: .local)
    let interval = try ArrayValue(sharing: array, subRange: 1..<2)
    let context = Context()

    _ = await context.snapshot(of: Object(value: interval))
    let localSpace = await context.localVMAllocationSpace

    #expect(array.allocation.membership(in: localSpace)?.isValid == true)
    #expect(nested.allocation.membership(in: localSpace)?.isValid == true)
  }

  @Test func restoreDoesNotChangeGlobalContainers() async throws {
    let global = try ArrayValue(elements: [1], access: .unlimited, vm: .global)
    let context = Context()
    try await context.pushAndRun(source: Object(value: global))
    let snapshot = try await context.snapshot()

    try global.updateObject(2, at: 0)
    try await snapshot.restore(to: context)

    #expect(try global.object(at: 0).value(as: IntegerValue.self).value == 2)
  }

  @Test func preservesDistinctEqualStringStorageMutations() async throws {
    let first = StringValue(string: "same", access: .unlimited, vm: .local)
    let second = StringValue(string: "same", access: .unlimited, vm: .local)
    let dictionary = try DictionaryValue(
      value: ["first": Object(value: first), "second": Object(value: second)],
      access: .unlimited,
      vm: .local
    )
    let context = Context()
    let snapshot = await context.snapshot(of: Object(value: dictionary))

    try first.updateCharacter(65, at: 0)
    try second.updateCharacter(66, at: 0)
    try await snapshot.restore(to: context)

    #expect(first.string == "Aame")
    #expect(second.string == "Bame")
  }

  @Test func preservesStringMutationsReachableThroughPackedArrays() async throws {
    let string = StringValue(string: "value", access: .unlimited, vm: .local)
    let packedArray = PackedArrayValue(elements: [Object(value: string)])
    let context = Context()
    let snapshot = await context.snapshot(of: Object(value: packedArray))

    try string.updateCharacter(88, at: 0)
    try await snapshot.restore(to: context)

    #expect(string.string == "Xalue")
  }

  @Test func failedValidationDoesNotConsumeSnapshot() async throws {
    let context = Context()
    let snapshot = try await context.snapshot()
    let newerObject = try await context.makeArrayAfterCurrentBoundary()
    await context.pushOperand(newerObject)

    await #expect(throws: Error.invalidRestore) {
      try await snapshot.restore(to: context)
    }

    _ = try await context.popOperand()
    try await snapshot.restore(to: context)
  }

  @Test func concurrentRestoreHasExactlyOneWinner() async throws {
    let context = Context()
    let snapshot = try await context.snapshot()

    async let first = restore(snapshot, to: context)
    async let second = restore(snapshot, to: context)
    let results = await [first, second]

    #expect(results.filter { $0 == nil }.count == 1)
    #expect(results.filter { $0 == .invalidRestore }.count == 1)
  }

  @Test func foreignContextRestoreFailsWithoutConsumingSnapshot() async throws {
    let owner = Context()
    let snapshot = try await owner.snapshot()

    await #expect(throws: Error.invalidRestore) {
      try await snapshot.restore(to: Context())
    }

    try await snapshot.restore(to: owner)
  }

  @Test func restoringOlderLanguageSaveInvalidatesNewerSnapshots() async throws {
    let context = Context()
    let older = try await context.registeredSnapshot()
    let newer = try await context.registeredSnapshot()

    try await older.restore(to: context)

    await #expect(throws: Error.invalidRestore) {
      try await newer.restore(to: context)
    }
  }

  @Test func failedValidationDoesNotCloseOrInvalidateNewerFiles() async throws {
    let context = Context()
    let snapshot = try await context.snapshot()
    let file = MaterializedFilterFile(
      data: Data("data".utf8),
      name: "generation-test",
      positionable: false,
      closeAtEnd: true
    )
    let allocation = try await context.register(file: file, vm: .local)
    let localSpace = await context.localVMAllocationSpace
    let newerObject = try await context.makeArrayAfterCurrentBoundary()
    await context.pushOperand(newerObject)

    await #expect(throws: Error.invalidRestore) {
      try await snapshot.restore(to: context)
    }
    #expect(!file.isClosed)
    #expect(allocation.membership(in: localSpace)?.isValid == true)

    _ = try await context.popOperand()
    try await snapshot.restore(to: context)
    #expect(file.isClosed)
    #expect(allocation.membership(in: localSpace)?.isValid == false)
  }

  @Test func discardedLocalAllocationCannotBeReintroduced() async throws {
    let context = Context()
    let snapshot = try await context.snapshot()
    let discarded = try await context.makeArrayAfterCurrentBoundary()

    try await snapshot.restore(to: context)

    await #expect(throws: Error.invalidAccess) {
      try await context.pushAndRun(source: discarded)
    }
  }

  private func restore(_ snapshot: Snapshot, to context: Context) async -> Error? {
    do {
      try await snapshot.restore(to: context)
      return nil
    } catch let error as Error {
      return error
    } catch {
      Issue.record("Unexpected restore error: \(error)")
      return nil
    }
  }
}

extension Context {

  fileprivate func snapshot(of object: Object) -> Snapshot {
    try! adopt(object)
    let builder = Snapshot.builder(for: self)
    object.save(to: builder)
    return builder.build()
  }

  fileprivate func pushOperand(_ object: Object) {
    try! adopt(object)
    operands.push(object)
  }

  fileprivate func popOperand() throws -> Object {
    try operands.pop()
  }

  fileprivate func makeArrayAfterCurrentBoundary() async throws -> Object {
    try await withUserTimeAccounting {
      try .array([], access: .unlimited, vm: .local, kind: .literal)
    }
  }

  fileprivate func registeredSnapshot() throws -> Snapshot {
    let snapshot = try self.snapshot()
    registerLanguageSave(snapshot)
    return snapshot
  }
}
