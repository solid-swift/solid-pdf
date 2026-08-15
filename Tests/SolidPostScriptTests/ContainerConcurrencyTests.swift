//
//  ContainerConcurrencyTests.swift
//

import Foundation
import Testing

@testable import SolidPostScript

@Suite
struct ContainerConcurrencyTests {

  @Test func arrayIntervalsShareStorage() throws {
    let array = try ArrayValue(elements: [0, 1, 2, 3, 4], access: .unlimited, vm: .local)
    let interval = try ArrayValue(sharing: array, subRange: 1..<4)

    try interval.updateObject(99, at: 1)

    #expect(try array.object(at: 2).value(as: IntegerValue.self).value == 99)
  }

  @Test func arrayConcurrentWritesPreserveEveryElement() async throws {
    let count = 128
    let array = try ArrayValue(
      elements: Array(repeating: .null, count: count),
      access: .unlimited,
      vm: .local
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<count {
        group.addTask {
          try array.updateObject(.integer(index), at: UInt(index))
        }
      }
      try await group.waitForAll()
    }

    for index in 0..<count {
      #expect(try array.object(at: UInt(index)).value(as: IntegerValue.self).value == index)
    }
  }

  @Test func arrayAccessIsScopedToTheValue() throws {
    let array = try ArrayValue(elements: [1], access: .unlimited, vm: .local)
    var restricted = array
    try restricted.setAccess(to: .readOnly)

    #expect(throws: Error.invalidAccess) {
      try restricted.updateObject(2, at: 0)
    }
    try array.updateObject(3, at: 0)
    #expect(try array.object(at: 0).value(as: IntegerValue.self).value == 3)
  }

  @Test func dictionaryAliasesShareStorage() throws {
    let dictionary = try DictionaryValue(value: [:], access: .unlimited, vm: .local)
    let alias = DictionaryValue(sharing: dictionary)

    try dictionary.updateObject(42, forKey: "answer")

    #expect(try alias.objectValue(forKey: "answer", as: IntegerValue.self).value == 42)
    #expect(try alias.removeObject(forKey: "answer") != nil)
    #expect(try dictionary.object(forKeyIfExists: "answer") == nil)
  }

  @Test func dictionaryConcurrentWritesPreserveEveryEntry() async throws {
    let count = 128
    let dictionary = try DictionaryValue(value: [:], access: .unlimited, vm: .local)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<count {
        group.addTask {
          try dictionary.updateObject(.integer(index), forKey: .literalName("key-\(index)"))
        }
      }
      try await group.waitForAll()
    }

    #expect(dictionary.count == count)
    for index in 0..<count {
      let value = try dictionary.objectValue(
        forKey: .literalName("key-\(index)"),
        as: IntegerValue.self
      )
      #expect(value.value == index)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func opposingDictionaryCopiesDoNotDeadlock() async throws {
    let first = try DictionaryValue(value: ["first": 1], access: .unlimited, vm: .local)
    let second = try DictionaryValue(value: ["second": 2], access: .unlimited, vm: .local)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try first.updateObjects(forKeysIn: second) }
      group.addTask { try second.updateObjects(forKeysIn: first) }
      try await group.waitForAll()
    }

    #expect(try first.object(forKeyIfExists: "second") != nil)
    #expect(try second.object(forKeyIfExists: "first") != nil)
  }

  @Test func dictionaryAccessIsSharedByAliases() throws {
    let dictionary = try DictionaryValue(value: [:], access: .unlimited, vm: .local)
    let alias = DictionaryValue(sharing: dictionary)

    try dictionary.setAccess(to: .readOnly)

    #expect(alias.access == .readOnly)
    #expect(throws: Error.invalidAccess) {
      try alias.updateObject(1, forKey: "value")
    }
  }

  @Test func stringIntervalsShareStorage() throws {
    let string = StringValue(string: "abcde", access: .unlimited, vm: .local)
    let interval = try StringValue(sharing: string, subRange: 1..<4)

    try interval.updateCharacter(0x78, at: 1)

    #expect(string.string == "abxde")
    #expect(interval.string == "bxd")
  }

  @Test func stringConcurrentReadsAndWritesAreSafe() async throws {
    let count = 128
    let string = StringValue(data: Data(repeating: 0, count: count), access: .unlimited, vm: .local)

    let readCounts = try await withThrowingTaskGroup(of: Int?.self, returning: [Int].self) { group in
      for index in 0..<count {
        group.addTask {
          try string.updateCharacter(UInt8(index), at: UInt(index))
          return nil
        }
        group.addTask {
          return try string.characters(in: string.range).count
        }
      }

      var results: [Int] = []
      for try await result in group {
        if let result {
          results.append(result)
        }
      }
      return results
    }

    #expect(readCounts.allSatisfy { $0 == count })
    #expect(try string.characters(in: string.range) == Data((0..<count).map(UInt8.init)))
  }

  @Test(.timeLimit(.minutes(1)))
  func opposingStringComparisonsDoNotDeadlock() async throws {
    let first = StringValue(string: "abc", access: .unlimited, vm: .local)
    let second = StringValue(string: "xyz", access: .unlimited, vm: .local)

    await withTaskGroup(of: ComparisonResult.self) { group in
      for _ in 0..<128 {
        group.addTask { first.compare(second) }
        group.addTask { second.compare(first) }
      }

      for await result in group {
        #expect(result != .orderedSame)
      }
    }
  }

  @Test func stringBoundsAndAccessAreEnforced() throws {
    var string = StringValue(string: "abc", access: .unlimited, vm: .local)
    #expect(throws: Error.rangeCheck) {
      try string.character(at: 3)
    }

    try string.setAccess(to: .readOnly)
    #expect(throws: Error.invalidAccess) {
      try string.updateCharacter(0, at: 0)
    }
  }

  @Test func packedArraysAreReadOnlyAndSendable() throws {
    let packed = PackedArrayValue(elements: [1, 2, 3])
    requireSendable(packed)

    #expect(PackedArrayValue.maxAccess == .readOnly)
    #expect(try packed.object(at: 1).value(as: IntegerValue.self).value == 2)
  }

  private func requireSendable<T: Sendable>(_: T) {}
}
