//
//  OperandStack.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

struct OperandStack {

  typealias Storage = Stack<Object>

  private var storage: Storage
  private var maximumDepth = Int.max
  private var overflowed = false

  init(_ items: [Object] = []) {
    self.storage = Stack(items)
  }

  init(storage: Stack<Object>) {
    self.storage = storage
  }

  var isEmpty: Bool { storage.isEmpty }
  var depth: Int { storage.depth }

  mutating func setMaximumDepth(_ maximumDepth: Int) {
    self.maximumDepth = maximumDepth
  }

  mutating func reserveAdditionalDepth(_ count: Int) -> Int {
    let previousMaximum = maximumDepth
    let (reservedMaximum, overflow) = max(maximumDepth, depth).addingReportingOverflow(count)
    maximumDepth = overflow ? .max : reservedMaximum
    return previousMaximum
  }

  mutating func throwIfOverflowed() throws {
    guard overflowed else { return }
    overflowed = false
    throw Error.stackOverflow
  }

  func peekAs<R: ObjectValue>(at position: Int = 0, as: R.Type = R.self) throws -> R {
    guard position >= 0 else {
      throw Error.rangeCheck
    }
    let index = storage.index(storage.startIndex, offsetBy: position)
    guard index < storage.endIndex else {
      throw Error.stackUnderflow
    }
    guard let op = storage[index].value as? R else {
      throw Error.typeCheck
    }
    return op
  }

  mutating func peek() throws -> Object {
    let ops = try peek(count: 1)
    return ops[ops.startIndex]
  }

  mutating func peek2() throws -> (Object, Object) {
    let ops = try peek(count: 2)
    return (
      ops[ops.index(ops.startIndex, offsetBy: 0)],
      ops[ops.index(ops.startIndex, offsetBy: 1)]
    )
  }

  mutating func peek3() throws -> (Object, Object, Object) {
    let ops = try peek(count: 3)
    return (
      ops[ops.index(ops.startIndex, offsetBy: 0)],
      ops[ops.index(ops.startIndex, offsetBy: 1)],
      ops[ops.index(ops.startIndex, offsetBy: 2)]
    )
  }

  mutating func peek4() throws -> (Object, Object, Object, Object) {
    let ops = try peek(count: 4)
    return (
      ops[ops.index(ops.startIndex, offsetBy: 0)],
      ops[ops.index(ops.startIndex, offsetBy: 1)],
      ops[ops.index(ops.startIndex, offsetBy: 2)],
      ops[ops.index(ops.startIndex, offsetBy: 3)]
    )
  }

  func peek(at position: Int) throws -> Object {
    guard position >= 0 else {
      throw Error.rangeCheck
    }
    let index = storage.index(storage.startIndex, offsetBy: position)
    guard index < storage.endIndex else {
      throw Error.stackUnderflow
    }
    return storage[index]
  }

  func peek(count: Int) throws -> some Collection<Object> {
    guard count >= 0 else {
      throw Error.rangeCheck
    }
    return try peek(bounds: 0..<count)
  }

  func peek(bounds: Range<Int>) throws -> some Collection<Object> {
    guard bounds.lowerBound >= 0, bounds.upperBound >= bounds.lowerBound else {
      throw Error.rangeCheck
    }
    guard bounds.upperBound <= depth else {
      throw Error.stackUnderflow
    }
    let startIndex = storage.index(storage.startIndex, offsetBy: bounds.lowerBound)
    let endIndex = storage.index(storage.startIndex, offsetBy: bounds.upperBound)
    return storage[startIndex..<endIndex]
  }

  mutating func popAs<each R: ObjectValue>(
    _ as: (repeat each R).Type = (repeat each R).self
  ) throws -> (repeat each R) {

    var count = 0
    func inc(_: Any.Type) { count += 1 }
    repeat inc((each R).self)

    var ops = try self.pop(count: count)

    return try (repeat ops.removeFirst().value(as: (each R).self))
  }

  mutating func pop() throws -> Object {
    let ops = try pop(count: 1)
    return ops[ops.startIndex]
  }

  mutating func pop2() throws -> (Object, Object) {
    let ops = try pop(count: 2)
    return (
      ops[ops.index(ops.startIndex, offsetBy: 0)],
      ops[ops.index(ops.startIndex, offsetBy: 1)]
    )
  }

  mutating func pop3() throws -> (Object, Object, Object) {
    let ops = try pop(count: 3)
    return (
      ops[ops.index(ops.startIndex, offsetBy: 0)],
      ops[ops.index(ops.startIndex, offsetBy: 1)],
      ops[ops.index(ops.startIndex, offsetBy: 2)]
    )
  }

  mutating func pop4() throws -> (Object, Object, Object, Object) {
    let ops = try pop(count: 4)
    return (
      ops[ops.index(ops.startIndex, offsetBy: 0)],
      ops[ops.index(ops.startIndex, offsetBy: 1)],
      ops[ops.index(ops.startIndex, offsetBy: 2)],
      ops[ops.index(ops.startIndex, offsetBy: 3)]
    )
  }

  mutating func pop(count: Int) throws -> [Object] {
    guard count >= 0 else {
      throw Error.rangeCheck
    }
    guard depth >= count else {
      throw Error.stackUnderflow
    }
    return Array(storage.pop(count))
  }

  mutating func push(_ element: Object) {
    guard depth < maximumDepth else {
      overflowed = true
      return
    }
    storage.push(element)
  }

  mutating func push(_ element: Object, _ elements: Object...) {
    push(contentsOf: [element] + elements)
  }

  mutating func push(contentsOf elements: some Sequence<Object>) {
    let elements = Array(elements)
    guard elements.count <= maximumDepth - min(depth, maximumDepth) else {
      overflowed = true
      return
    }
    storage.push(contentsOf: elements)
  }

  mutating func pushUnchecked(_ element: Object) {
    storage.push(element)
  }

  mutating func recoverFromOverflow(with element: Object) {
    storage = Stack([element])
    overflowed = false
  }

  subscript(position: Storage.Index) -> Object {
    storage[storage.index(storage.startIndex, offsetBy: position)]
  }

  func firstIndex(where predicate: (Object) -> Bool) -> Int? {
    for (idx, obj) in storage.enumerated() where predicate(obj) {
      return idx
    }
    return nil
  }

  func forEach(_ block: (Object) throws -> Void) throws {
    try storage.forEach(block)
  }

  func countToMark() throws -> Int {
    guard let count = firstIndex(where: { $0.type == .mark }) else {
      throw Error.unmatchedMmark
    }
    return count
  }

  mutating func popToMark() throws -> some Collection<Object> {
    let count = try countToMark()
    return try pop(count: count + 1).dropLast()
  }
}
