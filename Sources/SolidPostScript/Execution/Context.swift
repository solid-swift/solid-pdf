//
//  Context.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

/// Actor-isolated state for a PostScript interpreter execution.
public actor Context {

  struct ErrorInvocation {
    let error: Error
    let command: Object
    let operandStack: [Object]
    let executionStack: [Object]
    let dictionaryStack: [Object]
  }

  /// An PostScript execution mode.
  public enum ExecutionMode: Sendable {
    case immediate
    case deferred
  }

  /// A PostScript packing mode.
  public enum PackingMode: Sendable {
    case packed
    case unpacked
  }

  typealias RandomGenerator = PostScriptRandomNumberGenerator
  var random = RandomGenerator(seed: Int32.random(in: .min ... .max))

  let start = Date.timeIntervalSinceReferenceDate
  let fileDevices = FileDevices()

  var operands = OperandStack()
  var dictionaries = DictionaryStack(defaultDictionaries())
  var execution = ExecutionStack()
  var allocationMode: VM = .local
  var executionModes: Stack<ExecutionMode> = [.immediate]
  var packingMode: PackingMode = .unpacked
  var activeErrors: [ErrorInvocation] = []
  var resolvingErrorNames: Set<String> = []

  internal var executionMode: ExecutionMode {
    executionModes.peek().neverNil("Mode stack overflow")
  }

  internal func pushAndRun(source: Object) throws {
    try execution.push(source: source, in: self)
    try run(untilExecutionDepth: 0)
  }

  nonisolated static let deferredExecutionNames = [
    Operators.Defer.systemDictionaryNames,
    Operators.ConstructProcedure.systemDictionaryNames,
  ]
  .flatMap { $0 }

  nonisolated static let targetLanguageLevel: Int32 = 3

  // These are the PLRM-defined local roots that a global system dictionary may retain.
  nonisolated static let localSystemDictionaryNames: Set<Object> = [
    "$error",
    "errordict",
    "statusdict",
    "userdict",
  ]

  internal func run(untilExecutionDepth targetDepth: Int) throws {

    try Task<Never, Never>.checkCancellation()
    var iterationsUntilCancellationCheck = 256

    while execution.depth > targetDepth, let iterator = execution.peek()?.iterator {

      iterationsUntilCancellationCheck -= 1
      if iterationsUntilCancellationCheck == 0 {
        try Task<Never, Never>.checkCancellation()
        iterationsUntilCancellationCheck = 256
      }

      let savedOperands = operands
      let object: Object

      do {
        guard let nextObject = try iterator.next(context: self) else {
          _ = execution.pop()
          continue
        }

        object = nextObject
      } catch let error as Error {
        guard error.postScriptName != nil else {
          throw error
        }

        let command = execution.peek()?.source ?? .null
        try initiate(error: error, command: command, savedOperands: savedOperands)
        continue
      }

      if executionMode == .immediate || Self.deferredExecutionNames.contains(object) {
        try object.execute(context: self, method: .direct)
      } else {
        operands.push(object)
      }
    }
  }

  internal func execute(object: Object, method: Object.AccessMethod) throws {
    let savedOperands = operands

    do {
      if object.kind == .executable {
        try object.value.execute(context: self, kind: object.kind, method: method)
      } else {
        operands.push(object)
      }
    } catch let error as Error {
      guard error.postScriptName != nil else {
        throw error
      }

      try initiate(error: error, command: object, savedOperands: savedOperands)
    }
  }

  private func initiate(error: Error, command: Object, savedOperands: OperandStack) throws {
    let invocation = try makeErrorInvocation(error: error, command: error.isExternal ? .null : command)

    if !error.isExternal {
      operands = savedOperands
      operands.push(command)
    }

    guard let handler = try resolveErrorHandler(for: error) else {
      return
    }

    activeErrors.append(invocation)
    defer { _ = activeErrors.popLast() }

    try executeErrorHandler(handler)
  }

  private func makeErrorInvocation(error: Error, command: Object) throws -> ErrorInvocation {
    let operandStack = Array(try operands.peek(count: operands.depth).reversed())
    let executionStack = Array(execution.map(\.source).reversed())
    let dictionaryStack = Array(try dictionaries.peek(count: dictionaries.depth).reversed())

    return ErrorInvocation(
      error: error,
      command: command,
      operandStack: operandStack,
      executionStack: executionStack,
      dictionaryStack: dictionaryStack
    )
  }

  private func resolveErrorHandler(for error: Error) throws -> Object? {
    let errorName = error.postScriptName.neverNil("Control errors do not have PostScript handlers")

    guard resolvingErrorNames.insert(errorName).inserted else {
      throw UndispatchedError(error: error)
    }
    defer { resolvingErrorNames.remove(errorName) }

    do {
      let errorDictionary = try systemDictionary().objectValue(forKey: "errordict", as: DictionaryValue.self)
      return try errorDictionary.object(forKey: .literalName(errorName))
    } catch let resolutionError as Error {
      guard resolutionError.postScriptName != nil else {
        throw resolutionError
      }

      let savedOperands = operands
      try initiate(error: resolutionError, command: .literalName(errorName), savedOperands: savedOperands)
      return nil
    }
  }

  private func executeErrorHandler(_ handler: Object) throws {
    let savedExecution = execution
    let targetDepth = execution.depth
    defer { execution = savedExecution }

    try handler.execute(context: self, method: .indirect)
    try run(untilExecutionDepth: targetDepth)
  }

  func executeDefaultErrorHandler(named errorName: String) throws {
    guard let invocation = activeErrors.last else {
      throw Error.control(.stop)
    }

    allocationMode = .local

    let errorState = try systemDictionary().objectValue(forKey: "$error", as: DictionaryValue.self)
    let recordStacks = try errorState.objectValue(forKey: "recordstacks", as: BooleanValue.self)

    try errorState.updateObject(.boolean(true), forKey: "newerror")
    try errorState.updateObject(.literalName(errorName), forKey: "errorname")
    try errorState.updateObject(invocation.command, forKey: "command")
    try errorState.updateObject(.null, forKey: "errorinfo")

    if recordStacks.value {
      try errorState.updateObject(makeLocalArray(invocation.operandStack), forKey: "ostack")
      try errorState.updateObject(makeLocalArray(invocation.executionStack), forKey: "estack")
      try errorState.updateObject(makeLocalArray(invocation.dictionaryStack), forKey: "dstack")
    }

    throw ErrorStop(error: invocation.error)
  }

  func executeHandleError() throws {
    let errorState = try systemDictionary().objectValue(forKey: "$error", as: DictionaryValue.self)
    try errorState.updateObject(.boolean(false), forKey: "newerror")
    try errorState.updateObject(.null, forKey: "errorinfo")
  }

  private func systemDictionary() throws -> DictionaryValue {
    try dictionaries.systemDictionary()
  }

  private func makeLocalArray(_ objects: [Object]) throws -> Object {
    try .array(objects, access: .unlimited, vm: .local, kind: .literal)
  }

  internal func executeIsolated(proc: Object, ops: [Object] = []) throws -> Bool {

    let saved = (operands, dictionaries)
    defer { (operands, dictionaries) = saved }

    return try execute(proc: proc, ops: ops)
  }

  internal func execute(proc: Object, ops: [Object] = []) throws -> Bool {

    let saved = execution
    let targetDepth = execution.depth
    try execution.push(source: proc, in: self)
    defer { execution = saved }

    do {
      operands.push(contentsOf: ops)

      try run(untilExecutionDepth: targetDepth)

      return true
    } catch Error.control(.exit) {
      return false
    }
  }

  internal func limitCheck(size: Int, objectType: ObjectType) throws {
    guard size >= 0 else {
      throw Error.rangeCheck
    }
    let allowed =
      switch objectType {
      case .array, .packedArray, .dictionary:
        size < 10_000_000
      case .string:
        size < (1024 * 1024 * 20)
      default:
        false
      }
    if !allowed {
      throw Error.limitCheck
    }
  }

  internal func snapshot() throws -> Snapshot {
    let builder = Snapshot.builder(for: self)

    let systemDictionary = try systemDictionary()
    for name in Self.localSystemDictionaryNames {
      try systemDictionary.object(forKey: name).save(to: builder)
    }

    for op in try operands.peek(count: operands.depth) {
      op.save(to: builder)
    }

    for dict in try dictionaries.peek(count: dictionaries.depth) {
      dict.save(to: builder)
    }

    for exec in execution {
      exec.source.save(to: builder)
    }

    return builder.build()
  }

  /// Performs the ``results`` operation.
  public func results() throws -> [Object] {
    return Array(try operands.peek(count: operands.depth))
  }

  /// Performs the ``peekOperand`` operation.
  public func peekOperand() throws -> Object { try operands.peek() }

  /// The ``dictionaryStackDepth`` value.
  public var dictionaryStackDepth: Int { dictionaries.depth }
  /// Performs the ``currentDictionary`` operation.
  public func currentDictionary() throws -> DictionaryValue { try dictionaries.currentDictionary() }
  /// Performs the ``popDictionary`` operation.
  public func popDictionary() throws -> Object { try dictionaries.pop() }

  /// Performs the ``defaultDictionaries`` operation.
  nonisolated public static func defaultDictionaries() -> [Object] {
    let userDict = defaultUserDictionary()
    let globalDict = defaultGlobalDictionary()
    let sysDict = defaultSystemDictionary(userDict: userDict, globalDict: globalDict)
    return [userDict, globalDict, sysDict]
  }

  /// Performs the ``defaultSystemDictionary`` operation.
  nonisolated public static func defaultSystemDictionary(userDict: Object, globalDict: Object) -> Object {

    let errorDictionary = defaultErrorDictionary()
    let errorState = defaultErrorState()
    let statusDictionary = neverThrow(
      try Object.dictionary([:], access: .unlimited, vm: .local, kind: .literal)
    )

    var dict: [Object: Object] = [

      // Constants
      "null": nil,
      "true": true,
      "false": false,

      // Dictionaries
      "$error": errorState,
      "errordict": errorDictionary,
      "globaldict": globalDict,
      "userdict": userDict,
      "statusdict": statusDictionary,

      // Aspirational target; unavailable language features remain undefined.
      "languagelevel": .integer(targetLanguageLevel),

      // Product & version strings
      "product": .string("SolidPostScript", access: .readOnly, vm: .global, kind: .literal),
      "version": .string("1", access: .readOnly, vm: .global, kind: .literal),
      "revision": 0,

      // Deterministic and privacy-preserving.
      "serialnumber": 0,
    ]

    for op in Operators.all {
      for name in op.systemDictionaryNames {
        dict[name] = .init(value: op)
      }
    }

    let dictValue = neverThrow(
      try DictionaryValue(
        systemDictionaryValue: dict,
        localDictionaryKeys: localSystemDictionaryNames
      )
    )
    _ = neverThrow(try dictValue.setObject(.dictionary(sharing: dictValue, kind: .literal), forKey: "systemdict"))
    neverThrow(try dictValue.setAccess(to: .readOnly))
    return .dictionary(sharing: dictValue, kind: .literal)
  }

  private nonisolated static func defaultErrorDictionary() -> Object {
    var handlers = DictionaryValue.Storage()

    for name in Error.registeredPostScriptNames {
      handlers[.literalName(name)] = .init(value: ErrorHandlerValue.standard(name))
    }
    handlers["handleerror"] = .init(value: ErrorHandlerValue.handle)

    return neverThrow(try .dictionary(handlers, access: .unlimited, vm: .local, kind: .literal))
  }

  private nonisolated static func defaultErrorState() -> Object {
    let operandStack = neverThrow(try Object.array([], access: .unlimited, vm: .local, kind: .literal))
    let executionStack = neverThrow(try Object.array([], access: .unlimited, vm: .local, kind: .literal))
    let dictionaryStack = neverThrow(try Object.array([], access: .unlimited, vm: .local, kind: .literal))

    let state: DictionaryValue.Storage = [
      "newerror": false,
      "errorname": nil,
      "command": nil,
      "errorinfo": nil,
      "ostack": operandStack,
      "estack": executionStack,
      "dstack": dictionaryStack,
      "recordstacks": true,
      "binary": false,
    ]

    return neverThrow(try .dictionary(state, access: .unlimited, vm: .local, kind: .literal))
  }

  /// Performs the ``defaultGlobalDictionary`` operation.
  nonisolated public static func defaultGlobalDictionary() -> Object {
    let dict: [Object: Object] = [:]
    return neverThrow(try .dictionary(dict, access: .unlimited, vm: .global, kind: .literal))
  }

  /// Performs the ``defaultUserDictionary`` operation.
  nonisolated public static func defaultUserDictionary() -> Object {
    let dict: [Object: Object] = [:]
    return neverThrow(try .dictionary(dict, access: .unlimited, vm: .local, kind: .literal))
  }

}
