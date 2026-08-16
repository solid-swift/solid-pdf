import Foundation
import Synchronization

/// Shared system and device state for one PostScript interpreter environment.
public final class InterpreterEnvironment: Sendable {
  let state = Mutex(SystemParameterState())
  private let globalVMUsage = Mutex<[UUID: Int]>([:])

  /// The file devices available to contexts created in this environment.
  public let fileDevices: FileDevices

  /// Creates an interpreter environment with the supplied file devices.
  public init(fileDevices: FileDevices = FileDevices()) {
    self.fileDevices = fileDevices
  }

  func userParameters() -> UserParameterState {
    state.withLock { $0.userDefaults }
  }

  func systemParameters() -> [String: ParameterValue] {
    state.withLock { $0.currentValues }
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
