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
    try await execute(content: content, environment: InterpreterEnvironment())
  }

  /// Executes PostScript content in a new context belonging to `environment`.
  public static func execute(content: String, environment: InterpreterEnvironment) async throws -> Context {
    try await execute(
      file: DataFile(data: content.data(using: .isoLatin1).neverNil(), mode: .read),
      environment: environment
    )
  }

  /// Executes this value in the supplied interpreter context.
  public static func execute(file: File) async throws -> Context {
    try await execute(file: file, environment: InterpreterEnvironment())
  }

  /// Executes a PostScript file in a new context belonging to `environment`.
  public static func execute(file: File, environment: InterpreterEnvironment) async throws -> Context {
    let result = try await render(file: file, to: NullGraphicsTarget(), environment: environment)
    return result.context
  }

  /// Renders PostScript content to a typed graphics target in a new environment.
  public static func render<Target: GraphicsTarget>(
    content: String,
    to target: Target
  ) async throws -> GraphicsRenderResult<Target.Output> {
    try await render(content: content, to: target, environment: InterpreterEnvironment())
  }

  /// Renders PostScript content to a typed graphics target in `environment`.
  public static func render<Target: GraphicsTarget>(
    content: String,
    to target: Target,
    environment: InterpreterEnvironment
  ) async throws -> GraphicsRenderResult<Target.Output> {
    try await render(
      file: DataFile(data: content.data(using: .isoLatin1).neverNil(), mode: .read),
      to: target,
      environment: environment
    )
  }

  /// Renders a PostScript file to a typed graphics target in a new environment.
  public static func render<Target: GraphicsTarget>(
    file: File,
    to target: Target
  ) async throws -> GraphicsRenderResult<Target.Output> {
    try await render(file: file, to: target, environment: InterpreterEnvironment())
  }

  /// Renders a PostScript file to a typed graphics target in `environment`.
  public static func render<Target: GraphicsTarget>(
    file: File,
    to target: Target,
    environment: InterpreterEnvironment
  ) async throws -> GraphicsRenderResult<Target.Output> {
    let source: Object = .file(file, access: .readOnly, vm: .local, kind: .executable)
    let colorSession = try target.colorEngine.makeSession(for: target.deviceDescriptor)
    let deviceRenderingSession = try target.deviceRenderingEngine.makeSession(for: target.deviceDescriptor)
    let fontSession = try target.fontEngine.makeSession(for: target.deviceDescriptor)
    let pageDeviceSession = try target.pageDeviceProvider.makeSession(for: target.deviceDescriptor)
    let renderer = try target.makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingSession,
      fontSession: fontSession
    )
    let context = Context(environment: environment)
    do {
      let output = try await context.render(
        source: source,
        pageDeviceSession: pageDeviceSession,
        renderer: renderer
      )
      return GraphicsRenderResult(context: context, output: output)
    } catch let stop as ErrorStop {
      throw stop.error
    } catch let undispatched as UndispatchedError {
      throw undispatched.error
    }
  }

  /// Performs the ``results`` operation.
  public static func results(content: String) async throws -> [Object] {
    let context = try await execute(content: content)
    return try await context.results()
  }

  /// Executes content in `environment` and returns the resulting operand stack.
  public static func results(content: String, environment: InterpreterEnvironment) async throws -> [Object] {
    let context = try await execute(content: content, environment: environment)
    return try await context.results()
  }

  /// Performs the ``result`` operation.
  public static func result<R, each RS>(
    content: String,
    as resultType: (R, repeat each RS).Type = (R, repeat each RS).self
  ) async throws -> (R, repeat each RS) {

    try await result(content: content, environment: InterpreterEnvironment(), as: resultType)
  }

  /// Executes content in `environment` and converts the resulting operands to the requested tuple.
  public static func result<R, each RS>(
    content: String,
    environment: InterpreterEnvironment,
    as resultType: (R, repeat each RS).Type = (R, repeat each RS).self
  ) async throws -> (R, repeat each RS) {

    var iterator = try await results(content: content, environment: environment).makeIterator()

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

    try await result(content: content, count: count, environment: InterpreterEnvironment(), as: resultType)
  }

  /// Executes content in `environment` and converts `count` resulting operands.
  public static func result<R>(
    content: String,
    count: Int,
    environment: InterpreterEnvironment,
    as resultType: R.Type = R.self
  ) async throws -> [R] {

    guard count >= 0 else {
      throw Error.rangeCheck
    }

    var iterator = try await results(content: content, environment: environment).makeIterator()

    func pop() throws -> Object {
      guard let result = iterator.next() else {
        throw Error.stackUnderflow
      }
      return result
    }

    return try (0..<count).map { _ in try pop().value(as: R.self) }
  }
}
