//
//  Interpreter.swift
//
//
//  Created by Kevin Wooten on 6/25/24.
//

import Foundation
import SolidCore

/// Entry points for executing PostScript programs.
public enum Interpreter {

  /// Executes this value in the supplied interpreter context.
  public static func execute(content: String) async throws -> Context {
    try await execute(file: DataFile(data: content.data(using: .isoLatin1).neverNil(), mode: .read))
  }

  /// Executes this value in the supplied interpreter context.
  public static func execute(file: File) async throws -> Context {
    let source: Object = .file(file, access: .readOnly, vm: .local, kind: .executable)
    let context = Context()
    do {
      try await context.pushAndRun(source: source)
    } catch let stop as ErrorStop {
      throw stop.error
    } catch let undispatched as UndispatchedError {
      throw undispatched.error
    }
    return context
  }

  /// Performs the ``results`` operation.
  public static func results(content: String) async throws -> [Object] {
    let context = try await execute(content: content)
    return try await context.results()
  }

  /// Performs the ``result`` operation.
  public static func result<R, each RS>(
    content: String,
    as resultType: (R, repeat each RS).Type = (R, repeat each RS).self
  ) async throws -> (R, repeat each RS) {

    var iterator = try await results(content: content).makeIterator()

    func pop() throws -> Object {
      guard let result = iterator.next() else {
        throw Error.stackUnderflow
      }
      return result
    }

    return (
      try pop().value(as: R.self),
      repeat try pop().value(as: (each RS).self)
    )
  }

  /// Performs the ``result`` operation.
  public static func result<R>(content: String, count: Int, as resultType: R.Type = R.self) async throws -> [R] {

    guard count >= 0 else {
      throw Error.rangeCheck
    }

    var iterator = try await results(content: content).makeIterator()

    func pop() throws -> Object {
      guard let result = iterator.next() else {
        throw Error.stackUnderflow
      }
      return result
    }

    return try (0..<count).map { _ in try pop().value(as: R.self) }
  }
}
