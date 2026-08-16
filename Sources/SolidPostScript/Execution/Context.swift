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
  let environment: InterpreterEnvironment
  let fileDevices: FileDevices
  private let vmAccountingID = UUID()

  var operands = OperandStack()
  var dictionaries: DictionaryStack
  var execution = ExecutionStack()
  var userParameters: UserParameterState
  var allocationMode: VM = .local
  var objectFormat: ObjectFormat = .disabled
  var executionModes: Stack<ExecutionMode> = [.immediate]
  var packingMode: PackingMode = .unpacked
  var activeErrors: [ErrorInvocation] = []
  var resolvingErrorNames: Set<String> = []
  var stackLimitBypassDepth = 0
  var saveDepth = 0
  private var fileGeneration = 0
  private var openedLocalFiles: [(generation: Int, file: WeakFile)] = []

  init(environment: InterpreterEnvironment = InterpreterEnvironment()) {
    self.environment = environment
    self.fileDevices = environment.fileDevices
    let userParameters = environment.userParameters()
    self.userParameters = userParameters
    self.dictionaries = DictionaryStack(Self.defaultDictionaries(fileDevices: environment.fileDevices))
    self.operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    self.dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  init(fileDevices: FileDevices) {
    let environment = InterpreterEnvironment(fileDevices: fileDevices)
    self.environment = environment
    self.fileDevices = fileDevices
    let userParameters = environment.userParameters()
    self.userParameters = userParameters
    self.dictionaries = DictionaryStack(Self.defaultDictionaries(fileDevices: fileDevices))
    self.operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    self.dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  deinit {
    environment.removeGlobalVMUsage(for: vmAccountingID)
  }

  var stackLimitsBypassed: Bool { stackLimitBypassDepth > 0 }

  func applyUserParameterLimits() {
    operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

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
    "@Internal.Resources",
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
      let scanned: ScannedObject

      do {
        let nextObject = if let tokenIterator = iterator as? TokenObjectIterator {
          try tokenIterator.nextScanned(context: self)
        } else {
          try iterator.next(context: self).map { ScannedObject($0) }
        }

        guard let nextObject else {
          _ = execution.pop()
          continue
        }

        scanned = nextObject
      } catch let failure as ScannerFailure {
        try initiate(
          error: failure.error,
          command: scannerCommand(failure.command),
          savedOperands: savedOperands
        )
        continue
      } catch let error as Error {
        guard error.postScriptName != nil else {
          throw error
        }

        let command = execution.peek()?.source ?? .null
        try initiate(error: error, command: command, savedOperands: savedOperands)
        continue
      }

      let object = scanned.object

      if scanned.implicitlyExecutable && executionMode == .immediate {
        try object.execute(context: self, method: .indirect)
      } else if executionMode == .immediate || Self.deferredExecutionNames.contains(object) {
        try object.execute(context: self, method: .direct)
      } else {
        operands.push(object)
        do {
          try operands.throwIfOverflowed()
        } catch let error as Error {
          try initiate(error: error, command: object, savedOperands: savedOperands)
        }
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
      try operands.throwIfOverflowed()
    } catch let failure as ScannerFailure {
      try initiate(
        error: failure.error,
        command: scannerCommand(failure.command),
        savedOperands: savedOperands
      )
    } catch let error as Error {
      guard error.postScriptName != nil else {
        throw error
      }

      try initiate(error: error, command: object, savedOperands: savedOperands)
    }
  }

  private func scannerCommand(_ command: ScannerFailure.Command) -> Object {
    switch command {
    case .executableName(let name):
      .name(name, kind: .executable)
    case .string(let description):
      .string(description, access: .unlimited, vm: allocationMode, kind: .literal)
    }
  }

  private func initiate(error: Error, command: Object, savedOperands: OperandStack) throws {
    let invocation = try makeErrorInvocation(error: error, command: error.isExternal ? .null : command)

    if !error.isExternal {
      operands = savedOperands
      operands.pushUnchecked(command)
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

    stackLimitBypassDepth += 1
    do {
      try handler.execute(context: self, method: .indirect)
    } catch {
      stackLimitBypassDepth -= 1
      throw error
    }
    stackLimitBypassDepth -= 1
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
    let newError = try errorState.objectValue(forKey: "newerror", as: BooleanValue.self).value
    let binary = try errorState.objectValue(forKey: "binary", as: BooleanValue.self).value
    let errorName = try errorState.object(forKey: "errorname")
    let command = try errorState.object(forKey: "command")

    try errorState.updateObject(.boolean(false), forKey: "newerror")
    try errorState.updateObject(.null, forKey: "errorinfo")

    guard newError, binary, objectFormat.binaryEnabled else {
      return
    }

    let printableCommand = binaryErrorCommand(command)
    let report = try Object.array(
      [.literalName("Error"), errorName, printableCommand, .boolean(false)],
      access: .unlimited,
      vm: .local,
      kind: .literal
    )
    var encoder = BinaryObjectSequenceEncoder(format: objectFormat, tag: 250)
    try standardOutput().write(contentsOf: encoder.encode(report), context: self)
  }

  private func binaryErrorCommand(_ command: Object) -> Object {
    if let op = command.value as? any OperatorValue,
      let name = op.systemDictionaryNames.first?.value as? NameValue
    {
      return .name(name.value, kind: .executable)
    }

    do {
      var encoder = BinaryObjectSequenceEncoder(format: objectFormat, tag: 0)
      _ = try encoder.encode(command)
      return command
    } catch {
      return .name("--nostringval--", kind: .executable)
    }
  }

  private func systemDictionary() throws -> DictionaryValue {
    try dictionaries.systemDictionary()
  }

  private func makeLocalArray(_ objects: [Object]) throws -> Object {
    try .array(objects, access: .unlimited, vm: .local, kind: .literal)
  }

  internal func executeIsolated(proc: Object, ops: [Object] = []) throws -> Bool {

    let savedDictionaries = dictionaries
    defer { dictionaries = savedDictionaries }

    return try execute(proc: proc, ops: ops)
  }

  internal func execute(proc: Object, ops: [Object] = []) throws -> Bool {

    let saved = execution
    let targetDepth = execution.depth
    try execution.push(source: proc, in: self)
    defer { execution = saved }

    do {
      operands.push(contentsOf: ops)
      try operands.throwIfOverflowed()

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

    let requested = estimatedAllocationSize(count: size, objectType: objectType)
    try preflightAllocation(bytes: requested)
  }

  func estimatedVMUsage(in vm: VM) throws -> Int {
    let used = try estimatedReachableVMUsage(in: vm)
    guard vm == .global else { return used }
    return environment.updateGlobalVMUsage(for: vmAccountingID, to: used)
  }

  func preflightDictionaryGrowth(_ dictionary: DictionaryValue, key: Object) throws {
    guard try dictionary.object(forKeyIfExists: key) == nil else { return }
    try preflightAllocation(bytes: 16, vm: dictionary.vm)
  }

  func preflightAllocation(bytes: Int, vm: VM? = nil) throws {
    let vm = vm ?? allocationMode
    let used = try estimatedReachableVMUsage(in: vm)
    if vm == .global {
      _ = environment.updateGlobalVMUsage(for: vmAccountingID, to: used.saturatingAdd(bytes))
      return
    }
    let maximum = Int(userParameters.integer("MaxLocalVM"))
    guard bytes <= maximum - min(used, maximum) else { throw Error.vmError }
  }

  private func estimatedReachableVMUsage(in vm: VM) throws -> Int {
    var identities = Set<ObjectIdentifier>()
    var packedValues = Set<Object>()
    var used = 0

    func visit(_ object: Object) throws {
      guard let composite = object.value as? any CompositeValue else { return }

      if let identifiable = composite as? SnapshotIdentifiableValue {
        guard identities.insert(identifiable.snapshotIdentity).inserted else { return }
      } else if object.type == .packedArray {
        guard packedValues.insert(object).inserted else { return }
      }

      if composite.vm == vm {
        switch object.value {
        case let value as StringValue:
          used = used.saturatingAdd(Int(value.count) + 16)
        case let value as DictionaryValue:
          used = used.saturatingAdd(Int(value.count) * 16 + 32)
        case let value as any CollectionValue:
          used = used.saturatingAdd(Int(value.count) * 8 + 16)
        default:
          used = used.saturatingAdd(32)
        }
      }

      switch object.value {
      case let dictionary as DictionaryValue:
        try dictionary.forEachUnchecked { key, value in
          try visit(key)
          try visit(value)
        }
      case let collection as any CollectionValue:
        try collection.forEachUnchecked(visit)
      default:
        break
      }
    }

    try operands.forEach(visit)
    try dictionaries.forEach(visit)
    for item in execution {
      try visit(item.source)
    }
    return used
  }

  private func estimatedAllocationSize(count: Int, objectType: ObjectType) -> Int {
    switch objectType {
    case .string:
      count.saturatingAdd(16)
    case .array, .packedArray:
      count.saturatingMultiply(8).saturatingAdd(16)
    case .dictionary:
      count.saturatingMultiply(16).saturatingAdd(32)
    default:
      32
    }
  }

  internal func snapshot() throws -> Snapshot {
    let builder = Snapshot.builder(for: self, fileGeneration: fileGeneration)
    fileGeneration += 1

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

  func register(file: any File, vm: VM) {
    guard vm == .local else { return }
    openedLocalFiles.removeAll { $0.file.value == nil }
    openedLocalFiles.append((fileGeneration, WeakFile(file)))
  }

  func standardOutput() throws -> any File {
    try fileDevices.open(device: "stdout", name: "", mode: .write, openMethod: .truncateOrCreate)
  }

  func closeFiles(openedAfter generation: Int) {
    for tracked in openedLocalFiles where tracked.generation > generation {
      try? tracked.file.value?.close()
    }
    openedLocalFiles.removeAll { $0.generation > generation || $0.file.value == nil }
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
    defaultDictionaries(fileDevices: FileDevices())
  }

  private nonisolated static func defaultDictionaries(fileDevices: FileDevices) -> [Object] {
    let userDict = defaultUserDictionary()
    let globalDict = defaultGlobalDictionary()
    let sysDict = defaultSystemDictionary(userDict: userDict, globalDict: globalDict, fileDevices: fileDevices)
    return [userDict, globalDict, sysDict]
  }

  /// Performs the ``defaultSystemDictionary`` operation.
  nonisolated public static func defaultSystemDictionary(userDict: Object, globalDict: Object) -> Object {
    defaultSystemDictionary(userDict: userDict, globalDict: globalDict, fileDevices: FileDevices())
  }

  private nonisolated static func defaultSystemDictionary(
    userDict: Object,
    globalDict: Object,
    fileDevices: FileDevices
  ) -> Object {

    let errorDictionary = defaultErrorDictionary()
    let errorState = defaultErrorState()
    let statusDictionary = neverThrow(
      try Object.dictionary([:], access: .unlimited, vm: .local, kind: .literal)
    )
    let resourceCategories = neverThrow(
      try Object.dictionary(
        [
          "Filter": defaultFilterResourceDictionary(),
          "IODevice": defaultIODeviceResourceDictionary(fileDevices: fileDevices),
          "IdiomSet": defaultIdiomSetResourceDictionary(),
        ],
        access: .unlimited,
        vm: .local,
        kind: .literal
      )
    )

    var dict: [Object: Object] = [

      // Constants
      "null": nil,
      "true": true,
      "false": false,

      // Dictionaries
      "$error": errorState,
      "@Internal.Resources": resourceCategories,
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

  private nonisolated static func defaultFilterResourceDictionary() -> Object {
    var entries: [Object: Object] = [
      "Category": .literalName("Filter"),
      "DefineResource": Operators.DefineResource.default,
      "UndefineResource": Operators.UndefineResource.default,
      "FindResource": Operators.FindResource.default,
      "ResourceStatus": Operators.ResourceStatus.default,
      "ResourceForAll": Operators.ResourceForAll.default,
      "InstanceType": .literalName(ObjectType.name.name),
    ]
    for name in Operators.Filter.availableNames {
      entries[.literalName(name)] = .literalName(name)
    }
    return neverThrow(try .dictionary(entries, access: .unlimited, vm: .local, kind: .literal))
  }

  private nonisolated static func defaultIODeviceResourceDictionary(fileDevices: FileDevices) -> Object {
    var entries: [Object: Object] = [
      "Category": .literalName("IODevice"),
      "DefineResource": Operators.DefineResource.default,
      "UndefineResource": Operators.UndefineResource.default,
      "FindResource": Operators.FindResource.default,
      "ResourceStatus": Operators.ResourceStatus.default,
      "ResourceForAll": Operators.ResourceForAll.default,
      "InstanceType": .literalName(ObjectType.string.name),
    ]
    for device in fileDevices.registeredDevices {
      let identifier = "%\(device.name)%"
      entries[.literalName(identifier)] = .string(identifier, access: .readOnly, vm: .local, kind: .literal)
    }
    return neverThrow(try .dictionary(entries, access: .unlimited, vm: .local, kind: .literal))
  }

  private nonisolated static func defaultIdiomSetResourceDictionary() -> Object {
    let entries: [Object: Object] = [
      "Category": .literalName("IdiomSet"),
      "DefineResource": .init(value: Operators.DefineResource(extension: IdiomSetValidation.instance)),
      "UndefineResource": Operators.UndefineResource.default,
      "FindResource": Operators.FindResource.default,
      "ResourceStatus": Operators.ResourceStatus.default,
      "ResourceForAll": Operators.ResourceForAll.default,
      "InstanceType": .literalName(ObjectType.dictionary.name),
    ]
    return neverThrow(try .dictionary(entries, access: .unlimited, vm: .local, kind: .literal))
  }

}

private extension Int {
  func saturatingAdd(_ other: Int) -> Int {
    let (value, overflow) = addingReportingOverflow(other)
    return overflow ? .max : value
  }

  func saturatingMultiply(_ other: Int) -> Int {
    let (value, overflow) = multipliedReportingOverflow(by: other)
    return overflow ? .max : value
  }
}
