import Foundation
import SolidIO
import SolidTempo
import Synchronization

/// Shared system and device state for one PostScript interpreter environment.
public final class InterpreterEnvironment: Sendable {
  let state = Mutex(SystemParameterState())
  let globalVMAllocationSpace: VMAllocationSpace
  let nameTable: NameTable
  private let globalResources = Mutex(ResourceStore())
  private let resourcesInitialized = Mutex(false)
  let resourceCategories: [Object: any ResourceCategory]
  let standardInput: StandardInputChannel
  let standardOutput: StandardOutputChannel
  let standardError: StandardOutputChannel
  let standardErrorFile: StandardOutputFile
  let monotonicInstantSource: any MonotonicInstantSource

  /// The application integration used by this environment.
  public let hostConfiguration: InterpreterHostConfiguration

  /// The file devices available to contexts created in this environment.
  public let fileDevices: FileDevices

  /// Creates an interpreter environment with file devices and optional resource-category overrides.
  ///
  /// - Parameters:
  ///   - fileDevices: The file devices shared by contexts in this environment.
  ///   - resourceCategories: Category providers that augment or replace the standard registry.
  public convenience init(
    fileDevices: FileDevices = FileDevices(),
    resourceCategories: [Object: any ResourceCategory] = [:]
  ) {
    self.init(
      hostConfiguration: InterpreterHostConfiguration(),
      fileDevices: fileDevices,
      resourceCategories: resourceCategories
    )
  }

  /// Creates an interpreter environment whose `%stdout` device writes to `standardOutput`.
  ///
  /// The environment borrows the stream. Closing a PostScript `%stdout` file or destroying
  /// the environment does not close it.
  public convenience init(
    standardOutput: any Sink,
    fileDevices: FileDevices = FileDevices(),
    resourceCategories: [Object: any ResourceCategory] = [:]
  ) {
    self.init(
      hostConfiguration: InterpreterHostConfiguration(standardOutput: standardOutput),
      fileDevices: fileDevices,
      resourceCategories: resourceCategories
    )
  }

  /// Creates an interpreter environment using `hostConfiguration`.
  public convenience init(
    hostConfiguration: InterpreterHostConfiguration,
    fileDevices: FileDevices = FileDevices(),
    resourceCategories: [Object: any ResourceCategory] = [:]
  ) {
    self.init(
      hostConfiguration: hostConfiguration,
      fileDevices: fileDevices,
      resourceCategories: resourceCategories,
      monotonicInstantSource: UptimeInstantSource.instance
    )
  }

  init(
    hostConfiguration: InterpreterHostConfiguration = InterpreterHostConfiguration(),
    fileDevices: FileDevices = FileDevices(),
    resourceCategories: [Object: any ResourceCategory] = [:],
    monotonicInstantSource: any MonotonicInstantSource
  ) {
    let globalVMAllocationSpace = VMAllocationSpace(vm: .global)
    self.globalVMAllocationSpace = globalVMAllocationSpace
    self.nameTable = NameTable(globalVM: globalVMAllocationSpace)
    self.hostConfiguration = hostConfiguration
    let standardInput = StandardInputChannel(source: hostConfiguration.standardInput)
    let standardOutput = StandardOutputChannel(sink: hostConfiguration.standardOutput)
    let standardError = StandardOutputChannel(sink: hostConfiguration.standardError)
    let standardErrorFile = StandardOutputFile(channel: standardError, name: "stderr")
    self.standardInput = standardInput
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.standardErrorFile = standardErrorFile
    self.monotonicInstantSource = monotonicInstantSource
    self.fileDevices = fileDevices
      .replacing(StandardInputFileDevice(channel: standardInput))
      .replacing(StandardOutputFileDevice(channel: standardOutput, deviceName: "stdout"))
      .replacing(StandardOutputFileDevice(channel: standardError, deviceName: "stderr", sharedFile: standardErrorFile))
    var categories = Resources.resources
    categories.merge(resourceCategories) { _, replacement in replacement }
    if resourceCategories["IODevice"] == nil {
      categories["IODevice"] = IODeviceResources(fileDevices: self.fileDevices)
    }
    self.resourceCategories = categories
  }

  func startupProgram() async throws -> Data? {
    let mode = state.withLock { state -> Int32 in
      guard case .integer(let mode) = state.values["StartupMode"] else { return 0 }
      return mode
    }
    guard mode != 0 else { return nil }
    return try await hostConfiguration.startupProgramProvider.startupProgram(for: mode)
  }

  func authorize(_ request: JobAuthorizationRequest) async throws -> JobAuthorizationOutcome {
    if let provider = hostConfiguration.jobAuthorizationProvider {
      if let outcomeProvider = provider as? any JobAuthorizationOutcomeProvider {
        return try await outcomeProvider.authorizationOutcome(for: request)
      }
      return try await provider.authorize(request) ? .ordinary : .denied
    }
    return state.withLock { state in
      if state.systemPassword.isEmpty || request.candidate == state.systemPassword {
        return .administrator
      }
      if state.startJobPassword.isEmpty || request.candidate == state.startJobPassword {
        return .ordinary
      }
      return .denied
    }
  }

  func nextExecutiveEvent() async throws -> InteractiveExecutiveEvent {
    if let provider = hostConfiguration.interactiveExecutiveProvider {
      return try await provider.nextEvent()
    }
    guard let data = try await standardInput.read(max: 1024) else { return .endOfFile }
    return .data(data)
  }

  func emit(_ event: InterpreterLifecycleEvent) async throws {
    let observer = hostConfiguration.lifecycleObserver
    await observer.interpreter(didEmit: event)
    if let notice = await observer.notice(for: event) {
      try await standardOutput.write(notice)
    }
  }

  func ensureResourcesInitialized() throws {
    if resourcesInitialized.withLock({ $0 }) { return }

    let initial = try VMAllocationContext.$spaces.withValue(nil) {
      var initial = ResourceStore()
      for provider in resourceCategories.values {
        let descriptor = provider.dictionary
        try initial.define(
          ResourceEntry(instance: descriptor.object(), origin: .explicit, size: -1),
          for: .literalName(descriptor.category),
          in: .literalName("Category")
        )
      }
      let generic = try ResourceCategoryDictionary(
        category: "Generic",
        fileName: Operators.ResourceFileName.default
      ).object()
      try initial.define(
        ResourceEntry(instance: generic, origin: .explicit, size: -1),
        for: .literalName("Generic"),
        in: .literalName("Category")
      )
      return initial
    }

    resourcesInitialized.withLock { initialized in
      guard !initialized else { return }
      globalResources.withLock { $0 = initial }
      initialized = true
    }
  }

  func resourceCategory(for key: Object) throws -> (any ResourceCategory)? {
    resourceCategories[try canonicalResourceKey(key)]
  }

  func globalResource(for key: Object, in category: Object) throws -> ResourceEntry? {
    try ensureResourcesInitialized()
    return try globalResources.withLock { try $0.entry(for: key, in: category) }
  }

  func globalResourceEntries(in category: Object) throws -> [Object: ResourceEntry] {
    try ensureResourcesInitialized()
    return try globalResources.withLock { try $0.entries(in: category) }
  }

  @discardableResult
  func defineGlobalResource(_ entry: ResourceEntry, for key: Object, in category: Object) throws -> ResourceEntry? {
    try ensureResourcesInitialized()
    return try globalResources.withLock { try $0.define(entry, for: key, in: category) }
  }

  @discardableResult
  func removeGlobalResource(_ key: Object, from category: Object) throws -> ResourceEntry? {
    try ensureResourcesInitialized()
    return try globalResources.withLock { try $0.remove(key, from: category) }
  }

  func reclaimAutomaticGlobalResources() -> [GlobalResourceMutation] {
    guard resourcesInitialized.withLock({ $0 }) else { return [] }
    return globalResources.withLock { resources in
      resources.removeAutomaticEntries().map { removed in
        GlobalResourceMutation(
          key: removed.key,
          category: removed.category,
          previous: removed.entry,
          replacementID: nil
        )
      }
    }
  }

  func rollbackGlobalResourceMutations(_ mutations: [GlobalResourceMutation]) throws {
    try ensureResourcesInitialized()
    try globalResources.withLock { resources in
      for mutation in mutations.reversed() {
        let current = try resources.entry(for: mutation.key, in: mutation.category)
        guard current?.id == mutation.replacementID else { continue }
        if let previous = mutation.previous {
          try resources.define(previous, for: mutation.key, in: mutation.category)
        } else {
          _ = try resources.remove(mutation.key, from: mutation.category)
        }
      }
    }
  }

  func globalResourceObjects() throws -> [Object] {
    try ensureResourcesInitialized()
    return globalResources.withLock { $0.objects }
  }

  func userParameters() -> UserParameterState {
    state.withLock { $0.userDefaults }
  }

  func systemParameters() -> [String: ParameterValue] {
    state.withLock { $0.currentValues }
  }

  func systemString(_ name: String) -> String? {
    state.withLock { state in
      guard case .string(let data) = state.currentValues[name] else { return nil }
      return String(data: data, encoding: .isoLatin1)
    }
  }

  func updateSystemParameters(
    from dictionary: DictionaryValue,
    administrator: Bool = false
  ) throws {
    try dictionary.access.check(.read)
    var entries: [String: (key: Object, value: Object)] = [:]
    try dictionary.forEachUnchecked { key, value in
      let name = try PostScriptParameterFailure.wrapping(key: key, value: value) {
        try key.value(as: NameValue.self).value
      }
      entries[name] = (key, value)
    }

    let factoryOnly = Set(entries.keys).subtracting(["Password"]) == ["FactoryDefaults"]
    try state.withLock { state in
      if !factoryOnly, !administrator, !state.systemPassword.isEmpty {
        let passwordKey = Object.literalName("Password")
        guard let password = entries["Password"] else {
          throw PostScriptParameterFailure(error: .invalidAccess, key: passwordKey, value: nil)
        }
        let candidate = try PostScriptParameterFailure.wrapping(key: password.key, value: password.value) {
          try ParameterValue.password(from: password.value)
        }
        guard candidate == state.systemPassword else {
          throw PostScriptParameterFailure(error: .invalidAccess, key: password.key, value: password.value)
        }
      }

      var valueUpdates: [String: ParameterValue] = [:]
      var defaultUpdates: [String: ParameterValue] = [:]
      var nextSystemPassword: Data?
      var nextStartJobPassword: Data?

      for (name, entry) in entries where name != "Password" {
        if let definition = UserParameterState.definitions[name] {
          defaultUpdates[name] = try PostScriptParameterFailure.wrapping(key: entry.key, value: entry.value) {
            try definition.value(from: entry.value)
          }
          continue
        }
        guard let access = SystemParameterState.definitions[name] else { continue }
        switch access {
        case .readOnly:
          continue
        case .readWrite(let definition):
          valueUpdates[name] = try PostScriptParameterFailure.wrapping(key: entry.key, value: entry.value) {
            try definition.value(from: entry.value)
          }
        case .writeOnly:
          let password = try PostScriptParameterFailure.wrapping(key: entry.key, value: entry.value) {
            try ParameterValue.password(from: entry.value)
          }
          if name == "SystemParamsPassword" {
            nextSystemPassword = password
          } else {
            nextStartJobPassword = password
          }
        }
      }

      if case .string(let printerName) = valueUpdates["PrinterName"], printerName.isEmpty {
        valueUpdates["PrinterName"] = .string(Data("SolidPostScript".utf8))
      }

      let maxDisplay = updatedInteger("MaxDisplayList", updates: valueUpdates, current: state.values)
      let maxSource = updatedInteger("MaxSourceList", updates: valueUpdates, current: state.values)
      if let requestedCombined = updatedInteger(
        "MaxDisplayAndSourceList",
        updates: valueUpdates,
        current: state.values
      ) {
        valueUpdates["MaxDisplayAndSourceList"] = .integer(max(requestedCombined, max(maxDisplay ?? 0, maxSource ?? 0)))
      }

      state.values.merge(valueUpdates) { _, replacement in replacement }
      state.userDefaults.merge(defaultUpdates)
      if let nextSystemPassword { state.systemPassword = nextSystemPassword }
      if let nextStartJobPassword { state.startJobPassword = nextStartJobPassword }
    }
  }


  private func updatedInteger(
    _ name: String,
    updates: [String: ParameterValue],
    current: [String: ParameterValue]
  ) -> Int32? {
    guard case .integer(let value) = updates[name] ?? current[name] else { return nil }
    return value
  }

  func validateDevicePassword(
    in entries: [Object: Object],
    administrator: Bool = false
  ) throws -> [Object: Object] {
    var parameters = entries
    let passwordKey = Object.literalName("Password")
    let password = parameters.removeValue(forKey: passwordKey)
    try state.withLock { state in
      guard !administrator, !state.systemPassword.isEmpty else { return }
      guard let password else {
        throw PostScriptParameterFailure(error: .invalidAccess, key: passwordKey, value: nil)
      }
      let candidate = try PostScriptParameterFailure.wrapping(key: passwordKey, value: password) {
        try ParameterValue.password(from: password)
      }
      guard candidate == state.systemPassword else {
        throw PostScriptParameterFailure(error: .invalidAccess, key: passwordKey, value: password)
      }
    }
    return parameters
  }

}
