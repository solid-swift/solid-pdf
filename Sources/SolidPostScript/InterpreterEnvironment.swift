import Foundation
import SolidIO
import Synchronization

/// Shared system and device state for one PostScript interpreter environment.
public final class InterpreterEnvironment: Sendable {
  let state = Mutex(SystemParameterState())
  private let globalVMUsage = Mutex<[UUID: Int]>([:])
  private let globalResources = Mutex(ResourceStore())
  private let resourcesInitialized = Mutex(false)
  let resourceCategories: [Object: any ResourceCategory]
  let standardInput: StandardInputChannel
  let standardOutput: StandardOutputChannel
  let standardError: StandardOutputChannel

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
  public init(
    hostConfiguration: InterpreterHostConfiguration,
    fileDevices: FileDevices = FileDevices(),
    resourceCategories: [Object: any ResourceCategory] = [:]
  ) {
    self.hostConfiguration = hostConfiguration
    self.standardInput = StandardInputChannel(source: hostConfiguration.standardInput)
    self.standardOutput = StandardOutputChannel(sink: hostConfiguration.standardOutput)
    self.standardError = StandardOutputChannel(sink: hostConfiguration.standardError)
    self.fileDevices = fileDevices
      .replacing(StandardInputFileDevice(channel: self.standardInput))
      .replacing(StandardOutputFileDevice(channel: self.standardOutput, deviceName: "stdout"))
      .replacing(StandardOutputFileDevice(channel: self.standardError, deviceName: "stderr"))
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

  func authorize(_ request: JobAuthorizationRequest) async throws -> Bool {
    if let provider = hostConfiguration.jobAuthorizationProvider {
      return try await provider.authorize(request)
    }
    return state.withLock { state in
      request.candidate == state.startJobPassword || request.candidate == state.systemPassword
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

  func reclaimAutomaticGlobalResources() {
    globalResources.withLock { $0.removeAutomaticEntries() }
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

  func updateSystemParameters(from dictionary: DictionaryValue) throws {
    var entries: [String: Object] = [:]
    try dictionary.forEachUnchecked { key, value in
      entries[try key.value(as: NameValue.self).value] = value
    }

    let factoryOnly = Set(entries.keys).subtracting(["Password"]) == ["FactoryDefaults"]
    try state.withLock { state in
      if !factoryOnly, !state.systemPassword.isEmpty {
        guard let password = entries["Password"], try ParameterValue.password(from: password) == state.systemPassword else {
          throw Error.invalidAccess
        }
      }

      var valueUpdates: [String: ParameterValue] = [:]
      var defaultUpdates: [String: ParameterValue] = [:]
      var nextSystemPassword: Data?
      var nextStartJobPassword: Data?

      for (name, object) in entries where name != "Password" {
        if let definition = UserParameterState.definitions[name] {
          defaultUpdates[name] = try definition.value(from: object)
          continue
        }
        guard let access = SystemParameterState.definitions[name] else { continue }
        switch access {
        case .readOnly:
          continue
        case .readWrite(let definition):
          valueUpdates[name] = try definition.value(from: object)
        case .writeOnly:
          let password = try ParameterValue.password(from: object)
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

  func validateDevicePassword(in entries: [Object: Object]) throws -> [Object: Object] {
    var parameters = entries
    let passwordKey = Object.literalName("Password")
    let password = parameters.removeValue(forKey: passwordKey)
    try state.withLock { state in
      guard !state.systemPassword.isEmpty else { return }
      guard let password, try ParameterValue.password(from: password) == state.systemPassword else {
        throw Error.invalidAccess
      }
    }
    return parameters
  }

  func updateGlobalVMUsage(for context: UUID, to usage: Int) -> Int {
    globalVMUsage.withLock { usages in
      usages[context] = usage
      return usages.values.reduce(0) { result, value in result.saturatingAdd(value) }
    }
  }

  func removeGlobalVMUsage(for context: UUID) {
    _ = globalVMUsage.withLock { $0.removeValue(forKey: context) }
  }
}

private extension Int {
  func saturatingAdd(_ other: Int) -> Int {
    let (value, overflow) = addingReportingOverflow(other)
    return overflow ? .max : value
  }
}
