//
//  SnapshotConcurrencyTests.swift
//

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

  @Test func restoreDoesNotChangeGlobalContainers() async throws {
    let global = try ArrayValue(elements: [1], access: .unlimited, vm: .global)
    let context = Context()
    try await context.pushAndRun(source: Object(value: global))
    let snapshot = try await context.snapshot()

    try global.updateObject(2, at: 0)
    try await snapshot.restore(to: context)

    #expect(try global.object(at: 0).value(as: IntegerValue.self).value == 2)
  }

  @Test func failedValidationDoesNotConsumeSnapshot() async throws {
    let originalContext = try await Interpreter.execute(content: "save")
    let originalObject = try await originalContext.peekOperand()
    let originalSave = try #require(originalObject.value as? SaveValue)

    await Task.yield()
    let newerContext = try await Interpreter.execute(content: "save")
    let newerObject = try await newerContext.peekOperand()
    let newerSave = try #require(newerObject.value as? SaveValue)
    try #require(newerSave.snapshot.timestamp > originalSave.snapshot.timestamp)

    let invalidContext = Context()
    await invalidContext.pushOperand(newerObject)

    await #expect(throws: Error.invalidRestore) {
      try await originalSave.snapshot.restore(to: invalidContext)
    }

    try await originalSave.snapshot.restore(to: Context())
  }

  @Test func concurrentRestoreHasExactlyOneWinner() async throws {
    let source = try await Interpreter.execute(content: "save")
    let snapshot = try await source.peekOperand().value(as: SaveValue.self).snapshot

    async let first = restore(snapshot, to: Context())
    async let second = restore(snapshot, to: Context())
    let results = await [first, second]

    #expect(results.filter { $0 == nil }.count == 1)
    #expect(results.filter { $0 == .invalidRestore }.count == 1)
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
    let builder = Snapshot.builder(for: self)
    object.save(to: builder)
    return builder.build()
  }

  fileprivate func pushOperand(_ object: Object) {
    operands.push(object)
  }
}
