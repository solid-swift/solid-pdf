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
  var random = RandomGenerator(seed: Int.random(in: .min ... .max))

  let start = Date.timeIntervalSinceReferenceDate
  let fileDevices = FileDevices()

  var operands = OperandStack()
  var dictionaries = DictionaryStack(defaultDictionaries())
  var execution = ExecutionStack()
  var allocationMode: VM = .local
  var executionModes: Stack<ExecutionMode> = [.immediate]
  var packingMode: PackingMode = .unpacked

  internal var executionMode: ExecutionMode {
    executionModes.peek().neverNil("Mode stack overflow")
  }

  internal func pushAndRun(source: Object) throws {
    try execution.push(source: source, in: self)
    try run()
  }

  nonisolated static let deferredExecutionNames = [
    Operators.Defer.systemDictionaryNames,
    Operators.ConstructProcedure.systemDictionaryNames,
  ]
  .flatMap { $0 }

  internal func run(breakLoop: Bool = false) throws {

    try Task<Never, Never>.checkCancellation()
    var iterationsUntilCancellationCheck = 256

    while let iterator = execution.peek()?.iterator {

      iterationsUntilCancellationCheck -= 1
      if iterationsUntilCancellationCheck == 0 {
        try Task<Never, Never>.checkCancellation()
        iterationsUntilCancellationCheck = 256
      }

      guard let object = try iterator.next(context: self) else {
        _ = execution.pop()
        if breakLoop {
          break
        }
        continue
      }

      if executionMode == .immediate || Self.deferredExecutionNames.contains(object) {
        try object.execute(context: self, method: .direct)
      } else {
        operands.push(object)
      }
    }
  }

  internal func executeIsolated(proc: Object, ops: [Object] = []) throws -> Bool {

    let saved = (operands, dictionaries)
    defer { (operands, dictionaries) = saved }

    return try execute(proc: proc, ops: ops)
  }

  internal func execute(proc: Object, ops: [Object] = []) throws -> Bool {

    let saved = execution
    try execution.push(source: proc, in: self)
    defer { execution = saved }

    do {
      operands.push(contentsOf: ops)

      try run(breakLoop: true)

      return true
    } catch Error.control(.exit) {
      return false
    }
  }

  internal func limitCheck(size: Int, objectType: ObjectType) throws {
    let allowed =
      switch objectType {
      case .array, .packedArray, .dictionary:
        size > 0 && size < 10_000_000
      case .string:
        size > 0 && size < (1024 * 1024 * 20)
      default:
        false
      }
    if !allowed {
      throw Error.limitCheck
    }
  }

  internal func snapshot() throws -> Snapshot {
    let builder = Snapshot.builder(for: self)

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

    var dict: [Object: Object] = [

      // Constants
      "null": nil,
      "true": true,
      "false": false,

      // Dictionaries
      "errordict": [:],
      "globaldict": globalDict,
      "userdict": userDict,
      "statusdict": [:],

      // Required to be correct
      "languagelevel": 2,

      // Product & version strings
      // TODO: load from package/framework
      "product": "SolidPostScript",
      "version": "1",
      "revision": "0",

      // User identifiable properties (obscurred)
      "serialnumber": .literalName(UUID().uuidString),
    ]

    for op in Operators.all {
      for name in op.systemDictionaryNames {
        dict[name] = .init(value: op)
      }
    }

    let dictValue = neverThrow(try DictionaryValue(value: dict, access: .unlimited, vm: .local))
    _ = neverThrow(try dictValue.setObject(.dictionary(sharing: dictValue, kind: .literal), forKey: "systemdict"))
    neverThrow(try dictValue.setAccess(to: .readOnly))
    return .dictionary(sharing: dictValue, kind: .literal)
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
