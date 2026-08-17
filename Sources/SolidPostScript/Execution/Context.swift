//
//  Context.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore
import SolidTempo

/// Actor-isolated state for a PostScript interpreter execution.
public actor Context {

  private static let estimatedDictionaryEntryAllocationSize = 16

  struct JobLifecycle {
    let persistent: Bool
    let authorization: JobAuthorizationOutcome
    let snapshot: Snapshot?
    let startSaveDepth: Int
    let localBoundary: VMGenerationBoundary
    let globalBoundary: VMGenerationBoundary
    let resourceTransactionIndex: Int
  }

  private struct OpenedFile {
    let allocation: VMAllocation
    let file: WeakFile
  }

  struct ErrorInvocation {
    let error: Error
    let command: Object
    let errorInfo: PostScriptParameterFailure?
    let operandStack: [Object]
    let executionStack: [Object]
    let dictionaryStack: [Object]
  }

  struct FileReadAhead {
    let file: any File
    var data: Data
  }

  private enum StatementDelimiter {
    case literalString
    case procedure
    case array
    case dictionary
    case hexadecimalString
    case ascii85String
  }

  /// A legacy PostScript execution mode.
  @available(*, deprecated, message: "Procedure literals are constructed by the scanner")
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

  let environment: InterpreterEnvironment
  let fileDevices: FileDevices
  let userTime: Stopwatch
  let localVMAllocationSpace: VMAllocationSpace

  var operands = OperandStack()
  var dictionaries: DictionaryStack
  var execution = ExecutionStack()
  var userParameters: UserParameterState
  var allocationMode: VM = .local
  var objectFormat: ObjectFormat = .disabled
  var packingMode: PackingMode = .unpacked
  var activeErrors: [ErrorInvocation] = []
  var resolvingErrorNames: Set<String> = []
  var localResources = ResourceStore()
  var resourceLoadTransactions: [[GlobalResourceMutation]] = []
  var stackLimitBypassDepth = 0
  var saveDepth = 0
  var languageSaves: [Snapshot] = []
  var echoEnabled = true
  let jobServerEnabled: Bool
  var jobLifecycle: JobLifecycle?
  private var executivePendingInput = Data()
  private var snapshotSequence: UInt64 = 0
  private var openedFiles: [OpenedFile] = []
  private var standardFiles: [String: Object] = [:]
  var fileReadAhead: [ObjectIdentifier: FileReadAhead] = [:]
  var filePendingEndOfFile: [ObjectIdentifier: any File] = [:]
  private var executionBoundarySequence: UInt64 = 0
  private var executionTimingDepth = 0
  private var hostSuspensionDepth = 0

  init(environment: InterpreterEnvironment = InterpreterEnvironment(), jobServerEnabled: Bool = false) {
    let localVMAllocationSpace = VMAllocationSpace(vm: .local)
    self.environment = environment
    self.fileDevices = environment.fileDevices
    self.userTime = Stopwatch(source: environment.monotonicInstantSource)
    self.localVMAllocationSpace = localVMAllocationSpace
    self.jobServerEnabled = jobServerEnabled
    let userParameters = environment.userParameters()
    self.userParameters = userParameters
    let dictionaries = Self.defaultDictionaries(
      interactiveExecutiveEnabled: environment.hostConfiguration.interactiveExecutiveEnabled,
      jobServerEnabled: jobServerEnabled
    )
    self.dictionaries = DictionaryStack(dictionaries)
    neverThrow(try Self.adopt(dictionaries, into: VMAllocationSpaces(
      local: localVMAllocationSpace,
      global: environment.globalVMAllocationSpace
    )))
    self.operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    self.dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  init(fileDevices: FileDevices) {
    let environment = InterpreterEnvironment(fileDevices: fileDevices)
    let localVMAllocationSpace = VMAllocationSpace(vm: .local)
    self.environment = environment
    self.fileDevices = fileDevices
    self.userTime = Stopwatch(source: environment.monotonicInstantSource)
    self.localVMAllocationSpace = localVMAllocationSpace
    self.jobServerEnabled = false
    let userParameters = environment.userParameters()
    self.userParameters = userParameters
    let dictionaries = Self.defaultDictionaries()
    self.dictionaries = DictionaryStack(dictionaries)
    neverThrow(try Self.adopt(dictionaries, into: VMAllocationSpaces(
      local: localVMAllocationSpace,
      global: environment.globalVMAllocationSpace
    )))
    self.operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    self.dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  deinit {
    operands = OperandStack()
    dictionaries = DictionaryStack([Object]())
    localResources = ResourceStore()
    languageSaves.removeAll()
    activeErrors.removeAll()
    jobLifecycle = nil
    environment.globalVMAllocationSpace.collectCycles()
    localVMAllocationSpace.collectCycles()
  }

  var stackLimitsBypassed: Bool { stackLimitBypassDepth > 0 }

  private var allocationSpaces: VMAllocationSpaces {
    VMAllocationSpaces(local: localVMAllocationSpace, global: environment.globalVMAllocationSpace)
  }

  func adopt(_ object: Object) throws {
    try Self.adopt([object], into: allocationSpaces)
  }

  private nonisolated static func adopt(_ objects: some Sequence<Object>, into spaces: VMAllocationSpaces) throws {
    var visited = Set<ObjectIdentifier>()

    func visit(_ object: Object) throws {
      guard let composite = object.value as? VMAllocatedCompositeValue else { return }
      let allocation = composite.allocation
      guard visited.insert(allocation.identity).inserted else { return }
      try spaces.space(for: composite.vm).adopt(allocation, chargedBytes: composite.allocationFootprint)

      switch object.value {
      case let dictionary as DictionaryValue:
        try dictionary.forEachUnchecked { key, value in
          try visit(key)
          try visit(value)
        }
      case let collection as any SharedBackingArrayValue:
        try collection.forEachBackingUnchecked(visit)
      case let collection as any CollectionValue:
        try collection.forEachUnchecked(visit)
      default:
        break
      }
      composite.refreshStoredEdges()
    }

    for object in objects {
      try visit(object)
    }
  }

  func takeSnapshotSequence() -> UInt64 {
    precondition(snapshotSequence < .max, "PostScript snapshot sequence exhausted")
    snapshotSequence += 1
    return snapshotSequence
  }

  func recordGlobalResourceMutation(_ mutation: GlobalResourceMutation) {
    for index in resourceLoadTransactions.indices {
      resourceLoadTransactions[index].append(mutation)
    }
  }

  func applyUserParameterLimits() {
    operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  internal func pushAndRun(source: Object) async throws {
    try await withUserTimeAccounting {
      try establishStandardFiles()
      try execution.push(source: source, in: self)
      try await run(untilExecutionDepth: 0)
    }
  }

  func executeStart() async throws {
    try await withUserTimeAccounting {
      try establishStandardFiles()
      let targetDepth = execution.depth
      try await execute(object: .executableName("start"), method: .direct)
      try await run(untilExecutionDepth: targetDepth)
    }
  }

  func prepareIdiomResources() async throws {
    try await withUserTimeAccounting {
      let savedOperands = operands
      do {
        try await ResourceRuntime.preloadIdiomSets(context: self)
      } catch let error as ErrorStop {
        throw error
      } catch let error as UndispatchedError {
        throw error
      } catch let error as CancellationError {
        throw error
      } catch let failure as PostScriptParameterFailure {
        try await initiate(
          failure: failure,
          command: .executableName("findresource"),
          savedOperands: savedOperands
        )
      } catch let error as Error where error.postScriptName != nil {
        try await initiate(error: error, command: .executableName("findresource"), savedOperands: savedOperands)
      }
    }
  }

  func beginSessionJob() async throws {
    try await withUserTimeAccounting {
      try beginJob(persistent: false, authorization: .ordinary)
      try await prepareIdiomResources()
    }
  }

  func finishSessionJob() async throws {
    try await withUserTimeAccounting {
      try await finishJob()
    }
  }

  var currentJobPersistent: Bool { jobLifecycle?.persistent ?? false }
  var isSystemAdministratorJob: Bool { jobLifecycle?.authorization == .administrator }

  func reportCurrentError() async throws {
    try await withUserTimeAccounting {
      try await executeHandleError()
    }
  }

  func flush(file: any File) async throws {
    try await withUserTimeAccounting {
      try await file.flush(context: self)
    }
  }

  func withUserTimeAccounting<Result>(
    _ operation: () async throws -> Result
  ) async rethrows -> Result {
    try await VMAllocationContext.$spaces.withValue(allocationSpaces) {
      beginUserTimeAccounting()
      defer { endUserTimeAccounting() }
      return try await operation()
    }
  }

  func withUserTimeSuspended<Result>(
    _ operation: () async throws -> Result
  ) async rethrows -> Result {
    suspendUserTimeAccounting()
    defer { resumeUserTimeAccounting() }
    return try await operation()
  }

  private func beginUserTimeAccounting() {
    executionTimingDepth += 1
    guard executionTimingDepth == 1, hostSuspensionDepth == 0 else { return }
    userTime.start()
  }

  private func endUserTimeAccounting() {
    precondition(executionTimingDepth > 0, "Unbalanced PostScript execution timing scope")
    executionTimingDepth -= 1
    guard executionTimingDepth == 0, hostSuspensionDepth == 0 else { return }
    userTime.stop()
  }

  private func suspendUserTimeAccounting() {
    hostSuspensionDepth += 1
    guard hostSuspensionDepth == 1, executionTimingDepth > 0 else { return }
    userTime.stop()
  }

  private func resumeUserTimeAccounting() {
    precondition(hostSuspensionDepth > 0, "Unbalanced PostScript host suspension scope")
    hostSuspensionDepth -= 1
    guard hostSuspensionDepth == 0, executionTimingDepth > 0 else { return }
    userTime.start()
  }

  nonisolated static let targetLanguageLevel: Int32 = 3

  // These are the PLRM-defined local roots that a global system dictionary may retain.
  nonisolated static let localSystemDictionaryNames: Set<Object> = [
    "$error",
    "errordict",
    "statusdict",
    "userdict",
  ]

  internal func run(untilExecutionDepth targetDepth: Int) async throws {

    try Task<Never, Never>.checkCancellation()
    var iterationsUntilCancellationCheck = 256

    while execution.depth > targetDepth {

      guard let iterator = execution.peek()?.iterator else {
        preconditionFailure("Execution boundary exposed to the object runner")
      }

      iterationsUntilCancellationCheck -= 1
      if iterationsUntilCancellationCheck == 0 {
        try Task<Never, Never>.checkCancellation()
        iterationsUntilCancellationCheck = 256
      }

      let savedOperands = operands
      let scanned: ScannedObject

      do {
        let nextObject = if let tokenIterator = iterator as? TokenObjectIterator {
          try await tokenIterator.nextContextual(context: self)
        } else {
          try iterator.next(context: self).map { ScannedObject($0) }
        }

        guard let nextObject else {
          _ = execution.pop()
          continue
        }

        scanned = nextObject
      } catch let failure as ScannerFailure {
        try await initiate(
          error: failure.error,
          command: scannerCommand(failure.command),
          savedOperands: savedOperands
        )
        continue
      } catch let failure as PostScriptParameterFailure {
        let command = execution.peek()?.source ?? .null
        try await initiate(failure: failure, command: command, savedOperands: savedOperands)
        continue
      } catch let error as Error {
        guard error.postScriptName != nil else {
          throw error
        }

        let command = execution.peek()?.source ?? .null
        try await initiate(error: error, command: command, savedOperands: savedOperands)
        continue
      }

      let object = scanned.object

      if scanned.implicitlyExecutable {
        try await object.execute(context: self, method: .indirect)
      } else {
        try await object.execute(context: self, method: .direct)
      }
    }
  }

  internal func execute(object: Object, method: Object.AccessMethod) async throws {
    let savedOperands = operands

    do {
      if object.kind == .executable {
        try await object.value.execute(context: self, kind: object.kind, method: method)
      } else {
        operands.push(object)
      }
      try operands.throwIfOverflowed()
    } catch let failure as ScannerFailure {
      try await initiate(
        error: failure.error,
        command: scannerCommand(failure.command),
        savedOperands: savedOperands
      )
    } catch let failure as PostScriptParameterFailure {
      try await initiate(failure: failure, command: object, savedOperands: savedOperands)
    } catch let error as Error {
      guard error.postScriptName != nil else {
        throw error
      }

      try await initiate(error: error, command: object, savedOperands: savedOperands)
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

  private func initiate(
    failure: PostScriptParameterFailure,
    command: Object,
    savedOperands: OperandStack
  ) async throws {
    guard failure.error.postScriptName != nil else {
      throw failure.error
    }
    try await initiate(
      error: failure.error,
      errorInfo: failure,
      command: command,
      savedOperands: savedOperands
    )
  }

  private func initiate(
    error: Error,
    errorInfo: PostScriptParameterFailure? = nil,
    command: Object,
    savedOperands: OperandStack
  ) async throws {
    let invocation = try makeErrorInvocation(
      error: error,
      errorInfo: errorInfo,
      command: error.isExternal ? .null : command
    )

    if error == .stackOverflow {
      // PLRM 8.2 requires stackoverflow to expose the failure-time operand stack as
      // one local array instead of applying the ordinary error-initiation rollback.
      let recoveryStack = try makeLocalArray(invocation.operandStack)
      operands.recoverFromOverflow(with: recoveryStack)
    } else if !error.isExternal {
      operands = savedOperands
      operands.pushUnchecked(command)
    }

    guard let handler = try await resolveErrorHandler(for: error) else {
      return
    }

    activeErrors.append(invocation)
    defer { _ = activeErrors.popLast() }

    try await executeErrorHandler(handler)
  }

  private func makeErrorInvocation(
    error: Error,
    errorInfo: PostScriptParameterFailure?,
    command: Object
  ) throws -> ErrorInvocation {
    let operandStack = Array(try operands.peek(count: operands.depth).reversed())
    let executionStack = Array(execution.map(\.source).reversed())
    let dictionaryStack = Array(try dictionaries.peek(count: dictionaries.depth).reversed())

    return ErrorInvocation(
      error: error,
      command: command,
      errorInfo: errorInfo,
      operandStack: operandStack,
      executionStack: executionStack,
      dictionaryStack: dictionaryStack
    )
  }

  private func resolveErrorHandler(for error: Error) async throws -> Object? {
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
      try await initiate(error: resolutionError, command: .literalName(errorName), savedOperands: savedOperands)
      return nil
    }
  }

  private func executeErrorHandler(_ handler: Object) async throws {
    let savedExecution = execution
    let targetDepth = execution.depth
    defer { execution = savedExecution }

    stackLimitBypassDepth += 1
    do {
      try await handler.execute(context: self, method: .indirect)
    } catch {
      stackLimitBypassDepth -= 1
      throw error
    }
    stackLimitBypassDepth -= 1
    try await run(untilExecutionDepth: targetDepth)
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
    let errorInfo = try invocation.errorInfo.map {
      try makeLocalArray([$0.key, $0.value ?? .null])
    } ?? .null
    try errorState.updateObject(errorInfo, forKey: "errorinfo")

    // A VMerror handler must itself be able to run when no composite allocation is possible.
    if recordStacks.value, invocation.error != .vmError {
      try errorState.updateObject(makeLocalArray(invocation.operandStack), forKey: "ostack")
      try errorState.updateObject(makeLocalArray(invocation.executionStack), forKey: "estack")
      try errorState.updateObject(makeLocalArray(invocation.dictionaryStack), forKey: "dstack")
    }

    throw ErrorStop(error: invocation.error)
  }

  func executeHandleError() async throws {
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
    try await writeStandardOutput(encoder.encode(report))
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

  internal func executeIsolated(proc: Object, ops: [Object] = []) async throws {

    let savedDictionaries = dictionaries
    defer { dictionaries = savedDictionaries }

    try await execute(proc: proc, ops: ops)
  }

  internal func executeAny(_ object: Object) async throws {
    let saved = execution
    let targetDepth = execution.depth
    defer { execution = saved }

    try await object.execute(context: self, method: .indirect)
    try await run(untilExecutionDepth: targetDepth)
  }

  internal func execute(proc: Object, ops: [Object] = []) async throws {

    let saved = execution
    let targetDepth = execution.depth
    try execution.push(source: proc, in: self)
    defer { execution = saved }

    operands.push(contentsOf: ops)
    try operands.throwIfOverflowed()

    try await run(untilExecutionDepth: targetDepth)
  }

  internal func executeLoop(
    named operatorName: String,
    _ operation: () async throws -> Void
  ) async throws {
    let boundary = try pushExecutionBoundary(kind: .loop, named: operatorName)
    defer { execution.pop(boundary: boundary) }

    do {
      try await operation()
    } catch let transfer as LoopExitTransfer {
      guard transfer.boundaryIdentifier == boundary.identifier else {
        throw transfer
      }
    }
  }

  internal func executeStopped(_ object: Object) async throws -> Bool {
    let boundary = try pushExecutionBoundary(kind: .stopped, named: "stopped")
    defer { execution.pop(boundary: boundary) }

    do {
      try await executeAny(object)
      return false
    } catch Error.control(.stop) {
      return true
    } catch is ErrorStop {
      return true
    }
  }

  internal func executeRun(_ fileObject: Object) async throws {
    let file = try fileObject.value(as: FileValue.self).file
    let boundary: ExecutionBoundary
    do {
      boundary = try pushExecutionBoundary(kind: .run, named: "run")
    } catch {
      try? await closeLogicalFile(file)
      throw error
    }
    defer { execution.pop(boundary: boundary) }

    do {
      try await executeAny(fileObject)
      try await closeLogicalFile(file)
    } catch {
      try? await closeLogicalFile(file)
      throw error
    }
  }

  internal func exitDynamicallyEnclosingLoop() throws -> Never {
    for frame in execution {
      guard let boundary = frame.boundary else { continue }
      switch boundary.kind {
      case .loop:
        throw LoopExitTransfer(boundaryIdentifier: boundary.identifier)
      case .run, .stopped:
        throw Error.invalidExit
      }
    }

    throw Error.control(.quit)
  }

  private func pushExecutionBoundary(
    kind: ExecutionBoundary.Kind,
    named operatorName: String
  ) throws -> ExecutionBoundary {
    executionBoundarySequence &+= 1
    let boundary = ExecutionBoundary(identifier: executionBoundarySequence, kind: kind)
    try execution.push(boundary: boundary, source: .executableName(operatorName), in: self)
    return boundary
  }

  internal func limitCheck(
    size: Int,
    objectType: ObjectType,
    vm: VM? = nil,
    additionalDictionaryEntries: Int = 0
  ) throws {
    guard size >= 0 else {
      throw Error.rangeCheck
    }
    precondition(additionalDictionaryEntries >= 0)
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
      .saturatingAdd(additionalDictionaryEntries.saturatingMultiply(Self.estimatedDictionaryEntryAllocationSize))
    try preflightAllocation(bytes: requested, vm: vm)
  }

  func estimatedVMUsage(in vm: VM) throws -> Int {
    allocationSpaces.space(for: vm).chargedBytes
  }

  func remainingVMCapacity(in vm: VM) throws -> Int {
    let maximum = vm == .local ? Int(userParameters.integer("MaxLocalVM")) : Int(Int32.max)
    let used = try estimatedVMUsage(in: vm)
    return maximum - min(used, maximum)
  }

  func updateDictionary(
    _ dictionary: DictionaryValue,
    value: Object,
    forKey key: Object,
    additionalAllocationBytes: Int = 0
  ) throws {
    while true {
      let mutation = try dictionary.prepareUpdateObject(value, forKey: key)
      try preflightDictionaryMutation(
        mutation,
        in: dictionary,
        additionalAllocationBytes: additionalAllocationBytes
      )
      if try dictionary.commit(mutation) {
        return
      }
    }
  }

  func updateDictionary(_ dictionary: DictionaryValue, from source: DictionaryValue) throws {
    while true {
      let mutation = try dictionary.prepareUpdateObjects(forKeysIn: source)
      try preflightDictionaryMutation(mutation, in: dictionary)
      if try dictionary.commit(mutation) {
        return
      }
    }
  }

  private func preflightDictionaryMutation(
    _ mutation: DictionaryValue.PreparedMutation,
    in dictionary: DictionaryValue,
    additionalAllocationBytes: Int = 0
  ) throws {
    precondition(additionalAllocationBytes >= 0)
    let bytes = additionalAllocationBytes.saturatingAdd(mutation.allocationGrowthBytes)
    try preflightAllocation(bytes: bytes, vm: dictionary.vm)
  }

  func preflightAllocation(bytes: Int, vm: VM? = nil) throws {
    let vm = vm ?? allocationMode
    let reclaim = userParameters.integer("VMReclaim")
    let automaticCollection = vm == .local ? reclaim == 0 : reclaim >= -1
    let maximum = vm == .local ? Int(userParameters.integer("MaxLocalVM")) : nil
    let threshold = Int(userParameters.integer("VMThreshold"))
    guard allocationSpaces.space(for: vm).prepareForAllocation(
      bytes: bytes,
      maximum: maximum,
      automaticCollection: automaticCollection,
      threshold: threshold,
      beforeFullCollection: {
        ResourceRuntime.reclaimAutomaticResources(context: self, includeGlobal: vm == .global)
      }
    ) else {
      throw Error.vmError
    }
  }

  func estimatedAllocationSize(count: Int, objectType: ObjectType) -> Int {
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

  internal func snapshot(scope: Snapshot.Scope = .local) throws -> Snapshot {
    let builder = Snapshot.builder(for: self, scope: scope)

    if scope == .local {
      let systemDictionary = try systemDictionary()
      for name in Self.localSystemDictionaryNames {
        try systemDictionary.object(forKey: name).save(to: builder)
      }
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

  @discardableResult
  func register(file: any File, vm: VM) -> VMAllocation {
    let allocation = VMAllocationContext.allocation(in: vm)
    neverThrow(try allocationSpaces.space(for: vm).adopt(allocation))
    openedFiles.removeAll { $0.file.value == nil }
    openedFiles.append(OpenedFile(allocation: allocation, file: WeakFile(file)))
    return allocation
  }

  func openFileObject(name: String, mode modeString: String) throws -> Object {
    let parsed = PostScriptFileName(name)
    if let device = parsed.device, parsed.name.isEmpty, ["stdin", "stdout", "stderr"].contains(device) {
      let mode = try FileMode(string: modeString)
      let openMethod = try FileOpenMethod(string: modeString)
      switch (device, mode, openMethod) {
      case ("stdin", .read, .existingOnly),
        ("stdout", .write, .truncateOrCreate),
        ("stderr", .write, .truncateOrCreate):
        break
      default:
        throw Error.invalidFileAccess
      }
      guard let file = standardFiles[device] else {
        preconditionFailure("Standard PostScript files must be established before language execution")
      }
      return file
    }
    let file = try fileDevices.open(name: name, mode: modeString)
    let vm = allocationMode
    let allocation = register(file: file, vm: vm)
    return .file(file, access: file.mode.access, vm: vm, allocation: allocation, kind: .literal)
  }

  private func establishStandardFiles() throws {
    guard standardFiles.isEmpty else { return }

    let specifications: [(device: String, mode: FileMode, method: FileOpenMethod)] = [
      ("stdin", .read, .existingOnly),
      ("stdout", .write, .truncateOrCreate),
      ("stderr", .write, .truncateOrCreate),
    ]
    var opened: [(device: String, file: any File)] = []
    do {
      for specification in specifications {
        let file = try fileDevices.open(
          device: specification.device,
          name: "",
          mode: specification.mode,
          openMethod: specification.method
        )
        opened.append((specification.device, file))
      }
    } catch {
      for entry in opened {
        try? entry.file.close()
      }
      throw error
    }

    standardFiles = Dictionary(uniqueKeysWithValues: opened.map { entry in
      let allocation = register(file: entry.file, vm: .local)
      let object = Object.file(
        entry.file,
        access: entry.file.mode.access,
        vm: .local,
        allocation: allocation,
        kind: .literal
      )
      return (entry.device, object)
    })
  }

  private func retireStandardFiles() {
    let files = standardFiles.values.compactMap { $0.value as? FileValue }
    let allocations = Set(files.map { $0.allocation.identity })

    standardFiles.removeAll()
    for file in files {
      clearReadAhead(for: file.file)
      filePendingEndOfFile.removeValue(forKey: ObjectIdentifier(file.file))
      if !file.file.isClosed {
        try? file.file.close()
      }
    }
    openedFiles.removeAll {
      $0.file.value == nil || allocations.contains($0.allocation.identity)
    }
  }

  func beginJob(persistent: Bool, authorization: JobAuthorizationOutcome) throws {
    precondition(jobLifecycle == nil)
    precondition(authorization != .denied)
    // Standard category implementations are part of the environment's initial VM, even when
    // their backing dictionaries are created lazily for the first job.
    try environment.ensureResourcesInitialized()
    retireStandardFiles()
    localVMAllocationSpace.pruneWeakGarbage()
    let localBoundary = localVMAllocationSpace.boundary()
    let globalBoundary = environment.globalVMAllocationSpace.boundary()
    let snapshot = persistent ? nil : try snapshot(scope: .job)
    let resourceTransactionIndex = resourceLoadTransactions.count
    resourceLoadTransactions.append([])
    jobLifecycle = JobLifecycle(
      persistent: persistent,
      authorization: authorization,
      snapshot: snapshot,
      startSaveDepth: saveDepth,
      localBoundary: localBoundary,
      globalBoundary: globalBoundary,
      resourceTransactionIndex: resourceTransactionIndex
    )
    resetForJob()
    try establishStandardFiles()
  }

  func finishJob() async throws {
    guard let job = jobLifecycle else { return }
    operands = OperandStack()
    execution = ExecutionStack()
    dictionaries.clear()
    await closeFilesForJob(allocatedAfter: job.localBoundary, globalBoundary: job.globalBoundary)
    if job.persistent, let pendingSave = languageSaves.first {
      try pendingSave.restore(to: self)
    }
    if let snapshot = job.snapshot {
      try snapshot.restore(to: self)
    }
    guard job.resourceTransactionIndex < resourceLoadTransactions.count else {
      throw Error.invalidRestore
    }
    let mutations = resourceLoadTransactions.remove(at: job.resourceTransactionIndex)
    if !job.persistent {
      try environment.rollbackGlobalResourceMutations(mutations)
    }
    closeFiles(allocatedAfter: job.localBoundary, globalBoundary: job.globalBoundary)
    retireStandardFiles()
    jobLifecycle = nil
    languageSaves.removeAll()
  }

  func transitionJob(persistent: Bool, authorization: JobAuthorizationOutcome) async throws {
    let rootExecution = Array(execution).last
    try await finishJob()
    try beginJob(persistent: persistent, authorization: authorization)
    try await prepareIdiomResources()
    if let rootExecution {
      execution = ExecutionStack([rootExecution])
    }
  }

  private func resetForJob() {
    operands = OperandStack()
    execution = ExecutionStack()
    dictionaries.clear()
    allocationMode = .local
    objectFormat = .disabled
    packingMode = .unpacked
    userParameters = environment.userParameters()
    saveDepth = 0
    languageSaves.removeAll()
    echoEnabled = true
    activeErrors.removeAll()
    resolvingErrorNames.removeAll()
    localResources = ResourceStore()
    applyUserParameterLimits()
  }

  func registerLanguageSave(_ snapshot: Snapshot) {
    languageSaves.append(snapshot)
  }

  func didRestore(_ snapshot: Snapshot) {
    guard let index = languageSaves.firstIndex(where: { $0 === snapshot }) else { return }
    for invalidated in languageSaves[index...] where invalidated !== snapshot {
      invalidated.invalidate()
    }
    languageSaves.removeSubrange(index...)
  }

  func standardOutput() throws -> any File {
    guard let object = standardFiles["stdout"], let value = object.value as? FileValue else {
      preconditionFailure("Standard PostScript files must be established before language execution")
    }
    return value.file
  }

  func binaryErrorReportingEnabled() throws -> Bool {
    let state = try systemDictionary().objectValue(forKey: "$error", as: DictionaryValue.self)
    return try state.objectValue(forKey: "binary", as: BooleanValue.self).value
  }

  func writeStandardOutput(_ data: Data) async throws {
    try await withUserTimeSuspended {
      try await environment.standardOutput.write(data)
    }
  }

  func flushStandardOutput() async throws {
    try await withUserTimeSuspended {
      try await environment.standardOutput.flush()
    }
  }

  func openInteractiveFile(statement: Bool) async throws -> any File {
    guard environment.hostConfiguration.interactiveExecutiveEnabled else {
      throw Error.undefinedFilename
    }
    guard let data = try await readInteractiveInput(statement: statement) else {
      throw Error.undefinedFilename
    }
    return DataFile(data: data, mode: .read)
  }

  func runExecutive() async throws {
    guard environment.hostConfiguration.interactiveExecutiveEnabled else {
      throw Error.undefined
    }

    while true {
      do {
        let prompt = try dictionaries.object(forKey: "prompt")
        _ = try await execute(proc: prompt)

        guard let statement = try await readInteractiveInput(statement: true) else { return }
        let file = DataFile(data: statement, mode: .read)
        let source = Object.file(file, access: .readOnly, vm: .local, kind: .executable)
        _ = try await execute(proc: source)
      } catch Error.control(.quit) {
        return
      } catch is ErrorStop {
        try await executeHandleError()
        operands = OperandStack()
        dictionaries.clear()
      } catch Error.interrupt {
        do {
          try await initiate(error: .interrupt, command: .executableName("executive"), savedOperands: operands)
        } catch is ErrorStop {
          try await executeHandleError()
          operands = OperandStack()
          dictionaries.clear()
        }
      }
    }
  }

  private func readInteractiveInput(statement: Bool) async throws -> Data? {
    var result = Data()

    while true {
      if executivePendingInput.isEmpty {
        let event: InteractiveExecutiveEvent
        do {
          event = try await withUserTimeSuspended {
            try await environment.nextExecutiveEvent()
          }
        } catch is CancellationError {
          throw CancellationError()
        } catch let error as Error {
          throw error
        } catch {
          throw Error.ioError
        }
        switch event {
        case .data(let data):
          executivePendingInput.append(data)
        case .interrupt:
          throw Error.interrupt
        case .endOfFile:
          return result.isEmpty ? nil : result
        }
      }

      guard !executivePendingInput.isEmpty else { continue }
      let byte = executivePendingInput.removeFirst()

      switch byte {
      case 0x03:
        throw Error.interrupt
      case Scanner.backSpace, 0x7F:
        if !result.isEmpty { result.removeLast() }
      case 0x15:
        while let last = result.last, last != Scanner.lineFeed, last != Scanner.carriageReturn {
          result.removeLast()
        }
      case 0x12:
        if echoEnabled {
          let line = result.suffix { $0 != Scanner.lineFeed && $0 != Scanner.carriageReturn }
          try await writeStandardOutput(Data(line))
        }
      default:
        result.append(byte)
      }

      if echoEnabled, byte != 0x12 {
        try await writeStandardOutput(Data([byte]))
      }

      guard byte == Scanner.lineFeed || byte == Scanner.carriageReturn else { continue }
      if !statement || Self.isCompleteStatement(result) { return result }
    }
  }

  private nonisolated static func isCompleteStatement(_ data: Data) -> Bool {
    let bytes = Array(data)
    var delimiters: [StatementDelimiter] = []
    var escaped = false
    var comment = false
    var index = 0

    while index < bytes.count {
      let byte = bytes[index]
      if comment {
        if byte == Scanner.lineFeed || byte == Scanner.carriageReturn { comment = false }
        index += 1
        continue
      }
      if delimiters.last == .literalString {
        if escaped {
          escaped = false
        } else if byte == Scanner.escapeMarker {
          escaped = true
        } else if byte == Scanner.literalStringDelims.open {
          delimiters.append(.literalString)
        } else if byte == Scanner.literalStringDelims.close {
          _ = delimiters.popLast()
        }
        index += 1
        continue
      }
      if delimiters.last == .hexadecimalString {
        if byte == Scanner.char(">") { _ = delimiters.popLast() }
        index += 1
        continue
      }
      if delimiters.last == .ascii85String {
        if byte == Scanner.char("~"), bytes.indices.contains(index + 1), bytes[index + 1] == Scanner.char(">") {
          _ = delimiters.popLast()
          index += 2
        } else {
          index += 1
        }
        continue
      }
      switch byte {
      case Scanner.commentDelim:
        comment = true
      case Scanner.literalStringDelims.open:
        delimiters.append(.literalString)
      case Scanner.char("{"):
        delimiters.append(.procedure)
      case Scanner.char("["):
        delimiters.append(.array)
      case Scanner.char("<"):
        if bytes.indices.contains(index + 1), bytes[index + 1] == Scanner.char("<") {
          delimiters.append(.dictionary)
          index += 1
        } else if bytes.indices.contains(index + 1), bytes[index + 1] == Scanner.char("~") {
          delimiters.append(.ascii85String)
          index += 1
        } else {
          delimiters.append(.hexadecimalString)
        }
      case Scanner.literalStringDelims.close:
        if delimiters.last == .literalString { _ = delimiters.popLast() }
      case Scanner.char("}"):
        if delimiters.last == .procedure { _ = delimiters.popLast() }
      case Scanner.char("]"):
        if delimiters.last == .array { _ = delimiters.popLast() }
      case Scanner.char(">"):
        if delimiters.last == .dictionary,
          bytes.indices.contains(index + 1),
          bytes[index + 1] == Scanner.char(">")
        {
          _ = delimiters.popLast()
          index += 1
        }
      default:
        break
      }
      index += 1
    }
    return delimiters.isEmpty
  }

  func closeFiles(
    allocatedAfter localBoundary: VMGenerationBoundary,
    globalBoundary: VMGenerationBoundary?
  ) {
    for tracked in openedFiles where isAllocated(tracked.allocation, after: localBoundary, globalBoundary: globalBoundary) {
      if let file = tracked.file.value {
        clearReadAhead(for: file)
        try? file.close()
      }
    }
    openedFiles.removeAll {
      $0.file.value == nil || isAllocated($0.allocation, after: localBoundary, globalBoundary: globalBoundary)
    }
  }

  private func closeFilesForJob(
    allocatedAfter localBoundary: VMGenerationBoundary,
    globalBoundary: VMGenerationBoundary
  ) async {
    let files = openedFiles
      .filter { isAllocated($0.allocation, after: localBoundary, globalBoundary: globalBoundary) }
      .compactMap(\.file.value)
    for file in files {
      try? await file.close(context: self)
    }
  }

  private func isAllocated(
    _ allocation: VMAllocation,
    after localBoundary: VMGenerationBoundary,
    globalBoundary: VMGenerationBoundary?
  ) -> Bool {
    let boundary = allocation.vm == .local ? localBoundary : globalBoundary
    guard let boundary, let membership = allocation.membership(in: boundary.space) else { return false }
    return membership.generation > boundary.generation
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
    defaultDictionaries(interactiveExecutiveEnabled: true, jobServerEnabled: false)
  }

  nonisolated static func defaultDictionaries(
    interactiveExecutiveEnabled: Bool,
    jobServerEnabled: Bool
  ) -> [Object] {
    let userDict = defaultUserDictionary(jobServerEnabled: jobServerEnabled)
    let globalDict = defaultGlobalDictionary()
    let sysDict = defaultSystemDictionary(
      userDict: userDict,
      globalDict: globalDict,
      interactiveExecutiveEnabled: interactiveExecutiveEnabled,
      jobServerEnabled: jobServerEnabled
    )
    return [userDict, globalDict, sysDict]
  }

  /// Performs the ``defaultSystemDictionary`` operation.
  nonisolated public static func defaultSystemDictionary(userDict: Object, globalDict: Object) -> Object {
    defaultSystemDictionary(
      userDict: userDict,
      globalDict: globalDict,
      interactiveExecutiveEnabled: true,
      jobServerEnabled: false
    )
  }

  nonisolated static func defaultSystemDictionary(
    userDict: Object,
    globalDict: Object,
    interactiveExecutiveEnabled: Bool,
    jobServerEnabled: Bool
  ) -> Object {
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
      "shareddict": globalDict,
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
        if !interactiveExecutiveEnabled, name == "executive" || name == "echo" {
          continue
        }
        dict[name] = .init(value: op)
      }
    }
    dict["="] = Operators.equalsProcedure
    dict["=="] = Operators.doubleEqualsProcedure
    dict["start"] = Operators.startProcedure
    if interactiveExecutiveEnabled {
      dict["prompt"] = Operators.promptProcedure
    }
    if jobServerEnabled {
      dict["serverdict"] = Operators.serverDictionary
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
    defaultUserDictionary(jobServerEnabled: false)
  }

  nonisolated static func defaultUserDictionary(jobServerEnabled: Bool) -> Object {
    let dict: [Object: Object] = jobServerEnabled ? ["quit": Operators.quitMaskProcedure] : [:]
    return neverThrow(try .dictionary(dict, access: .unlimited, vm: .local, kind: .literal))
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
