//
//  TextOutputOps.swift
//

import Foundation
import SolidCore

extension Operators {

  static let textOutputOps: [OperatorValue] = [
    Print.instance,
    Stack.instance,
    PStack.instance,
  ]

  static let equalsProcedure = neverThrow(
    try Object.array(
      [Object(value: Equals.instance)],
      access: .readOnly,
      vm: .global,
      kind: .executable
    )
  )

  static let doubleEqualsProcedure = neverThrow(
    try Object.array(
      [Object(value: DoubleEquals.instance)],
      access: .readOnly,
      vm: .global,
      kind: .executable
    )
  )

  /// Implements the PostScript `print` operator.
  public enum Print: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["print"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let string: StringValue = try context.operands.popAs()
      try string.access.check(.read)
      try await context.writeStandardOutput(string.characters(in: string.range))
    }
  }

  enum Equals: OperatorValue {
    case instance

    static let systemDictionaryNames: [Object] = ["="]

    func execute(context: isolated Context) async throws {
      let object = try context.operands.pop()
      var formatter = PostScriptTextFormatter(mode: .value)
      var output = formatter.format(object)
      output.append(0x0A)
      try await context.writeStandardOutput(output)
    }
  }

  enum DoubleEquals: OperatorValue {
    case instance

    static let systemDictionaryNames: [Object] = ["=="]

    func execute(context: isolated Context) async throws {
      let object = try context.operands.pop()
      var formatter = PostScriptTextFormatter(mode: .syntax)
      var output = formatter.format(object)
      output.append(0x0A)
      try await context.writeStandardOutput(output)
    }
  }

  /// Implements the PostScript `stack` operator.
  public enum Stack: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["stack"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try await writeStack(context: context, mode: .value)
    }
  }

  /// Implements the PostScript `pstack` operator.
  public enum PStack: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["pstack"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try await writeStack(context: context, mode: .syntax)
    }
  }

  private static func writeStack(context: isolated Context, mode: PostScriptTextFormatter.Mode) async throws {
    let objects = Array(try context.operands.peek(count: context.operands.depth))
    var formatter = PostScriptTextFormatter(mode: mode)
    var output = Data()
    for object in objects {
      output.append(formatter.format(object))
      output.append(0x0A)
    }
    try await context.writeStandardOutput(output)
  }
}
