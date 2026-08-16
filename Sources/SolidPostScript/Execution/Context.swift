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

  private static let estimatedDictionaryEntryAllocationSize = 16

  struct JobLifecycle {
    let persistent: Bool
    let snapshot: Snapshot?
    let startSaveDepth: Int
    let fileGeneration: Int
    let resourceTransactionIndex: Int
  }

  struct ErrorInvocation {
    let error: Error
    let command: Object
    let operandStack: [Object]
    let executionStack: [Object]
    let dictionaryStack: [Object]
  }

  private enum StatementDelimiter {
    case literalString
    case procedure
    case array
    case dictionary
    case hexadecimalString
    case ascii85String
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
  var localResources = ResourceStore()
  var resourceLoadTransactions: [[GlobalResourceMutation]] = []
  var stackLimitBypassDepth = 0
  var saveDepth = 0
  var languageSaves: [Snapshot] = []
  var echoEnabled = true
  let jobServerEnabled: Bool
  var jobLifecycle: JobLifecycle?
  private var executivePendingInput = Data()
  private var fileGeneration = 0
  private var openedLocalFiles: [(generation: Int, file: WeakFile)] = []
  private var standardFiles: [String: any File] = [:]

  init(environment: InterpreterEnvironment = InterpreterEnvironment(), jobServerEnabled: Bool = false) {
    self.environment = environment
    self.fileDevices = environment.fileDevices
    self.jobServerEnabled = jobServerEnabled
    let userParameters = environment.userParameters()
    self.userParameters = userParameters
    self.dictionaries = DictionaryStack(
      Self.defaultDictionaries(
        interactiveExecutiveEnabled: environment.hostConfiguration.interactiveExecutiveEnabled,
        jobServerEnabled: jobServerEnabled
      )
    )
    self.operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    self.dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  init(fileDevices: FileDevices) {
    let environment = InterpreterEnvironment(fileDevices: fileDevices)
    self.environment = environment
    self.fileDevices = fileDevices
    self.jobServerEnabled = false
    let userParameters = environment.userParameters()
    self.userParameters = userParameters
    self.dictionaries = DictionaryStack(Self.defaultDictionaries())
    self.operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    self.dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  deinit {
    environment.removeGlobalVMUsage(for: vmAccountingID)
  }

  var stackLimitsBypassed: Bool { stackLimitBypassDepth > 0 }

  func recordGlobalResourceMutation(_ mutation: GlobalResourceMutation) {
    for index in resourceLoadTransactions.indices {
      resourceLoadTransactions[index].append(mutation)
    }
  }

  func applyUserParameterLimits() {
    operands.setMaximumDepth(Int(userParameters.integer("MaxOpStack")))
    dictionaries.setMaximumDepth(Int(userParameters.integer("MaxDictStack")))
  }

  internal var executionMode: ExecutionMode {
    executionModes.peek().neverNil("Mode stack overflow")
  }

  internal func pushAndRun(source: Object) async throws {
    try execution.push(source: source, in: self)
    try await run(untilExecutionDepth: 0)
  }

  func executeStart() async throws {
    let targetDepth = execution.depth
    try await execute(object: .executableName("start"), method: .direct)
    try await run(untilExecutionDepth: targetDepth)
  }

  func prepareIdiomResources() async throws {
    let savedOperands = operands
    do {
      try await ResourceRuntime.preloadIdiomSets(context: self)
    } catch let error as ErrorStop {
      throw error
    } catch let error as UndispatchedError {
      throw error
    } catch let error as CancellationError {
      throw error
    } catch let error as Error where error.postScriptName != nil {
      try await initiate(error: error, command: .executableName("findresource"), savedOperands: savedOperands)
    }
  }

  func beginSessionJob() async throws {
    try beginJob(persistent: false)
    try await prepareIdiomResources()
  }

  func finishSessionJob() async throws {
    try await finishJob()
  }

  var currentJobPersistent: Bool { jobLifecycle?.persistent ?? false }

  func reportCurrentError() async throws {
    try await executeHandleError()
  }

  func flush(file: any File) async throws {
    try await file.flush(context: self)
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

  internal func run(untilExecutionDepth targetDepth: Int) async throws {

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
      } catch let error as Error {
        guard error.postScriptName != nil else {
          throw error
        }

        let command = execution.peek()?.source ?? .null
        try await initiate(error: error, command: command, savedOperands: savedOperands)
        continue
      }

      let object = scanned.object

      if scanned.implicitlyExecutable && executionMode == .immediate {
        try await object.execute(context: self, method: .indirect)
      } else if executionMode == .immediate || Self.deferredExecutionNames.contains(object) {
        try await object.execute(context: self, method: .direct)
      } else {
        operands.push(object)
        do {
          try operands.throwIfOverflowed()
        } catch let error as Error {
          try await initiate(error: error, command: object, savedOperands: savedOperands)
        }
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

  private func initiate(error: Error, command: Object, savedOperands: OperandStack) async throws {
    let invocation = try makeErrorInvocation(error: error, command: error.isExternal ? .null : command)

    if !error.isExternal {
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
    try errorState.updateObject(.null, forKey: "errorinfo")

    if recordStacks.value {
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

  internal func executeIsolated(proc: Object, ops: [Object] = []) async throws -> Bool {

    let savedDictionaries = dictionaries
    defer { dictionaries = savedDictionaries }

    return try await execute(proc: proc, ops: ops)
  }

  internal func execute(proc: Object, ops: [Object] = []) async throws -> Bool {

    let saved = execution
    let targetDepth = execution.depth
    try execution.push(source: proc, in: self)
    defer { execution = saved }

    do {
      operands.push(contentsOf: ops)
      try operands.throwIfOverflowed()

      try await run(untilExecutionDepth: targetDepth)

      return true
    } catch Error.control(.exit) {
      return false
    }
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
    let used = try estimatedReachableVMUsage(in: vm)
    guard vm == .global else { return used }
    return environment.updateGlobalVMUsage(for: vmAccountingID, to: used)
  }

  func remainingVMCapacity(in vm: VM) throws -> Int {
    let maximum = vm == .local ? Int(userParameters.integer("MaxLocalVM")) : Int(Int32.max)
    let used = try estimatedVMUsage(in: vm)
    return maximum - min(used, maximum)
  }

  func preflightDictionaryGrowth(_ dictionary: DictionaryValue, key: Object) throws {
    guard try dictionary.object(forKeyIfExists: key) == nil else { return }
    try preflightAllocation(bytes: Self.estimatedDictionaryEntryAllocationSize, vm: dictionary.vm)
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
    if vm == .local {
      try localResources.objects.forEach(visit)
    } else {
      try environment.globalResourceObjects().forEach(visit)
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

  internal func snapshot(scope: Snapshot.Scope = .local) throws -> Snapshot {
    let builder = Snapshot.builder(for: self, fileGeneration: fileGeneration, scope: scope)
    fileGeneration += 1

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

  func register(file: any File, vm: VM) {
    guard vm == .local else { return }
    openedLocalFiles.removeAll { $0.file.value == nil }
    openedLocalFiles.append((fileGeneration, WeakFile(file)))
  }

  func openFile(name: String, mode modeString: String) throws -> any File {
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
      if let file = standardFiles[device] { return file }
      let file = try fileDevices.open(device: device, name: "", mode: mode, openMethod: openMethod)
      standardFiles[device] = file
      return file
    }
    return try fileDevices.open(name: name, mode: modeString)
  }

  func resetStandardFiles() {
    standardFiles.removeAll()
  }

  func beginJob(persistent: Bool) throws {
    precondition(jobLifecycle == nil)
    let jobFileGeneration = fileGeneration
    let snapshot = persistent ? nil : try snapshot(scope: .job)
    let resourceTransactionIndex = resourceLoadTransactions.count
    resourceLoadTransactions.append([])
    jobLifecycle = JobLifecycle(
      persistent: persistent,
      snapshot: snapshot,
      startSaveDepth: saveDepth,
      fileGeneration: jobFileGeneration,
      resourceTransactionIndex: resourceTransactionIndex
    )
    resetForJob()
  }

  func finishJob() async throws {
    guard let job = jobLifecycle else { return }
    operands = OperandStack()
    execution = ExecutionStack()
    dictionaries.clear()
    await closeFilesForJob(openedAfter: job.fileGeneration)
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
    closeFiles(openedAfter: 0)
    resetStandardFiles()
    jobLifecycle = nil
    languageSaves.removeAll()
  }

  func transitionJob(persistent: Bool) async throws {
    let rootExecution = Array(execution).last
    try await finishJob()
    try beginJob(persistent: persistent)
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
    executionModes = [.immediate]
    userParameters = environment.userParameters()
    saveDepth = 0
    languageSaves.removeAll()
    echoEnabled = true
    activeErrors.removeAll()
    resolvingErrorNames.removeAll()
    localResources = ResourceStore()
    applyUserParameterLimits()
    resetStandardFiles()
  }

  func registerLanguageSave(_ snapshot: Snapshot) {
    languageSaves.append(snapshot)
  }

  func didRestore(_ snapshot: Snapshot) {
    guard let index = languageSaves.firstIndex(where: { $0 === snapshot }) else { return }
    languageSaves.removeSubrange(index...)
  }

  func standardOutput() throws -> any File {
    try openFile(name: "%stdout", mode: "w")
  }

  func binaryErrorReportingEnabled() throws -> Bool {
    let state = try systemDictionary().objectValue(forKey: "$error", as: DictionaryValue.self)
    return try state.objectValue(forKey: "binary", as: BooleanValue.self).value
  }

  func writeStandardOutput(_ data: Data) async throws {
    try await environment.standardOutput.write(data)
  }

  func flushStandardOutput() async throws {
    try await environment.standardOutput.flush()
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
          event = try await environment.nextExecutiveEvent()
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

  func closeFiles(openedAfter generation: Int) {
    for tracked in openedLocalFiles where tracked.generation > generation {
      try? tracked.file.value?.close()
    }
    openedLocalFiles.removeAll { $0.generation > generation || $0.file.value == nil }
  }

  private func closeFilesForJob(openedAfter generation: Int) async {
    let files = openedLocalFiles
      .filter { $0.generation > generation }
      .compactMap(\.file.value)
    for file in files {
      try? await file.close(context: self)
    }
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
