//
//  ControlOps.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation
import SolidCore

extension Operators {

  static let controlOps: [OperatorValue] = [
    Exec.instance,
    If.instance,
    IfElse.instance,
    For.instance,
    Repeat.instance,
    Loop.instance,
    Exit.instance,
    Stop.instance,
    Stopped.instance,
    CountExecStack.instance,
    CopyExecStack.instance,
    Quit.instance,
  ]

  /// Implements the PostScript `exec` operator.
  public enum Exec: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["exec"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try await context.operands.pop().execute(context: context, method: .indirect)
    }
  }

  /// Implements the PostScript `if` operator.
  public enum If: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["if"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (proc, boolObj) = try context.operands.pop2()
      let bool = try boolObj.value(as: BooleanValue.self)
      try proc.checkProcedure()

      if bool.value {
        try context.execution.push(source: proc, in: context)
      }
    }
  }

  /// Implements the PostScript `ifelse` operator.
  public enum IfElse: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["ifelse"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (elseproc, ifproc, boolObj) = try context.operands.pop3()
      let bool = try boolObj.value(as: BooleanValue.self)
      try ifproc.checkProcedure()
      try elseproc.checkProcedure()

      try context.execution.push(source: bool.value ? ifproc : elseproc, in: context)
    }
  }

  /// Implements the PostScript `for` operator.
  public enum For: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["for"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (proc, limit, increment, initial) = try context.operands.pop4()
      try proc.checkProcedure()

      switch (initial.value, increment.value, limit.value) {
      case (let initial as IntegerValue, let increment as IntegerValue, let limit as IntegerValue):
        try await Self.executeIntegers(
          context: context,
          proc: proc,
          ops: (initial.value, increment.value, limit.value)
        )

      case (let initial as NumericConvertible, let increment as NumericConvertible, let limit as NumericConvertible):
        try await Self.execute(context: context, proc: proc, ops: (initial.real, increment.real, limit.real))

      default:
        throw Error.typeCheck
      }
    }

    typealias ExecArgs<T> = (initial: T, increment: T, limit: T)

    static func executeIntegers(
      context: isolated Context,
      proc: Object,
      ops: ExecArgs<Int32>
    ) async throws {
      var control = Int64(ops.initial)
      let increment = Int64(ops.increment)
      let limit = Int64(ops.limit)
      while increment >= 0 ? control <= limit : control >= limit {
        let controlObject = try NumericSemantics.integer(validating: control)
        if try await !context.execute(proc: proc, ops: [controlObject]) {
          break
        }
        control += increment
      }
    }

    static func execute<T>(context: isolated Context, proc: Object, ops: ExecArgs<T>) async throws
    where T: AdditiveArithmetic, T: Comparable, T: NumericObjectConvertible {

      var control = ops.initial
      while ops.increment >= .zero ? control <= ops.limit : control >= ops.limit {
        if try await !context.execute(proc: proc, ops: [try control.numericObject]) {
          break
        }
        control += ops.increment
      }
    }
  }

  /// Implements the PostScript `repeat` operator.
  public enum Repeat: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["repeat"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (proc, countObj) = try context.operands.pop2()
      let count = try countObj.value(as: IntegerValue.self)
      guard count.value >= 0 else {
        throw Error.rangeCheck
      }
      try proc.checkProcedure()

      for _ in 0..<count.value where try await !context.execute(proc: proc) {
        break
      }
    }
  }

  /// Implements the PostScript `loop` operator.
  public enum Loop: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["loop"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let proc = try context.operands.pop()
      try proc.checkProcedure()

      while true {
        if try await !context.execute(proc: proc) {
          break
        }
      }
    }
  }

  /// Implements the PostScript `exit` operator.
  public enum Exit: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["exit"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      throw Error.control(.exit)
    }
  }

  /// Implements the PostScript `stop` operator.
  public enum Stop: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["stop"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      throw Error.control(.stop)
    }
  }

  /// Implements the PostScript `stopped` operator.
  public enum Stopped: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["stopped"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let proc = try context.operands.pop()

      do {

        if try await !context.executeAny(proc) {
          throw Error.invalidExit
        }

        context.operands.push(.boolean(false))
      } catch Error.control(.stop) {

        context.operands.pushUnchecked(.boolean(true))
      } catch is ErrorStop {

        context.operands.pushUnchecked(.boolean(true))
      }
    }
  }

  /// Implements the PostScript `countexecstack` operator.
  public enum CountExecStack: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["countexecstack"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.operands.push(try NumericSemantics.integer(validating: context.execution.depth))
    }
  }

  /// Implements the PostScript `execstack` operator.
  public enum CopyExecStack: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["execstack"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let arrayObj = try context.operands.pop()
      let array = try arrayObj.value(as: ArrayValue.self)
      guard array.count >= context.execution.depth else {
        throw Error.rangeCheck
      }
      let execs = context.execution[context.execution.startIndex..<context.execution.endIndex]
      try array.updateObjects(execs.map { $0.source }.reversed(), startingAt: 0)
      context.operands.push(try .array(sharing: array, subRange: 0..<execs.count.unsigned, kind: arrayObj.kind))
    }
  }

  /// Implements the PostScript `quit` operator.
  public enum Quit: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["quit"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      if context.jobServerEnabled, context.jobLifecycle?.persistent != true {
        throw Error.invalidAccess
      }
      throw Error.control(.quit)
    }
  }
}
