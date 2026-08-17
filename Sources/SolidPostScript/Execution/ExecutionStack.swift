//
//  ExecutionStack.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation
import SolidCore

struct ExecutionBoundary: Sendable {
  enum Kind: Sendable {
    case loop
    case stopped
    case run
  }

  let identifier: UInt64
  let kind: Kind
}

enum ExecutionFrame {
  case object(source: Object, iterator: ObjectIterator)
  case boundary(source: Object, boundary: ExecutionBoundary)

  var source: Object {
    switch self {
    case .object(let source, _), .boundary(let source, _):
      source
    }
  }

  var iterator: ObjectIterator? {
    guard case .object(_, let iterator) = self else { return nil }
    return iterator
  }

  var boundary: ExecutionBoundary? {
    guard case .boundary(_, let boundary) = self else { return nil }
    return boundary
  }

  var isProcedure: Bool {
    guard case .object(let source, _) = self, source.kind == .executable else { return false }
    return source.value is ArrayValue || source.value is PackedArrayValue
  }
}

typealias ExecutionStack = Stack<ExecutionFrame>

extension ExecutionStack {

  mutating func push(source: Object, in context: isolated Context) throws {
    try context.adopt(source)
    try (source.value as? any CompositeValue)?.access.check(.execute)
    try checkCapacity(in: context)
    let value = try source.value(as: ObjectSource.self)
    let iterator = try value.makeIterator(context: context)
    push(.object(source: source, iterator: iterator))
  }

  mutating func push(
    boundary: ExecutionBoundary,
    source: Object,
    in context: isolated Context
  ) throws {
    try checkCapacity(in: context)
    push(.boundary(source: source, boundary: boundary))
  }

  mutating func pop(boundary: ExecutionBoundary) {
    precondition(peek()?.boundary?.identifier == boundary.identifier, "Unbalanced execution boundary")
    _ = pop()
  }

  private func checkCapacity(in context: isolated Context) throws {
    guard context.stackLimitsBypassed || depth < Int(context.userParameters.integer("MaxExecStack")) else {
      throw Error.executionStackOverflow
    }
  }

}
