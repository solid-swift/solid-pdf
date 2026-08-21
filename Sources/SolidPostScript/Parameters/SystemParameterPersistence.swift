import Foundation

enum SystemParameterPersistence {
  static let payloadVersion = 1
  static let maximumPayloadBytes = 4 * 1_024 * 1_024

  private struct Payload: Codable {
    let version: Int
    let systemValues: [String: StoredValue]
    let userDefaults: [String: StoredValue]
    let systemPassword: Data
    let startJobPassword: Data
  }

  private enum StoredValue: Codable {
    case boolean(Bool)
    case integer(Int32)
    case string(Data)

    private enum CodingKeys: String, CodingKey {
      case kind
      case boolean
      case integer
      case string
    }

    private enum Kind: String, Codable {
      case boolean
      case integer
      case string
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      switch try container.decode(Kind.self, forKey: .kind) {
      case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .boolean))
      case .integer: self = .integer(try container.decode(Int32.self, forKey: .integer))
      case .string: self = .string(try container.decode(Data.self, forKey: .string))
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .boolean(let value):
        try container.encode(Kind.boolean, forKey: .kind)
        try container.encode(value, forKey: .boolean)
      case .integer(let value):
        try container.encode(Kind.integer, forKey: .kind)
        try container.encode(value, forKey: .integer)
      case .string(let value):
        try container.encode(Kind.string, forKey: .kind)
        try container.encode(value, forKey: .string)
      }
    }

    init(_ value: ParameterValue) {
      switch value {
      case .boolean(let value): self = .boolean(value)
      case .integer(let value): self = .integer(value)
      case .string(let value): self = .string(value)
      }
    }

    var parameterValue: ParameterValue {
      switch self {
      case .boolean(let value): .boolean(value)
      case .integer(let value): .integer(value)
      case .string(let value): .string(value)
      }
    }
  }

  static func encode(_ state: SystemParameterState) throws -> Data {
    let systemValues = state.values.compactMapValues { value in StoredValue(value) }.filter { name, _ in
      guard let access = SystemParameterState.definitions[name] else { return name == "PageCount" }
      if case .readWrite = access { return true }
      return name == "PageCount"
    }
    let payload = Payload(
      version: payloadVersion,
      systemValues: systemValues,
      userDefaults: state.userDefaults.values.mapValues(StoredValue.init),
      systemPassword: state.systemPassword,
      startJobPassword: state.startJobPassword
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(payload)
    guard data.count <= maximumPayloadBytes else { throw CocoaError(.fileWriteOutOfSpace) }
    return data
  }

  static func decode(_ data: Data) -> SystemParameterState? {
    guard data.count <= maximumPayloadBytes,
      let payload = try? JSONDecoder().decode(Payload.self, from: data),
      payload.version == payloadVersion,
      payload.systemPassword.count <= maximumPayloadBytes,
      payload.startJobPassword.count <= maximumPayloadBytes
    else { return nil }

    var state = SystemParameterState()
    for (name, stored) in payload.systemValues {
      if name == "PageCount" {
        guard case .integer(let count) = stored.parameterValue, count >= 0 else { return nil }
        state.values[name] = .integer(count)
        continue
      }
      guard case .readWrite(let definition)? = SystemParameterState.definitions[name],
        let normalized = definition.normalize(stored.parameterValue),
        normalized == stored.parameterValue
      else { return nil }
      state.values[name] = normalized
    }

    var userDefaults = UserParameterState()
    for (name, stored) in payload.userDefaults {
      guard let definition = UserParameterState.definitions[name],
        let normalized = definition.normalize(stored.parameterValue),
        normalized == stored.parameterValue
      else { return nil }
      userDefaults.merge([name: normalized])
    }
    state.userDefaults = userDefaults
    state.systemPassword = payload.systemPassword
    state.startJobPassword = payload.startJobPassword
    return state
  }
}
