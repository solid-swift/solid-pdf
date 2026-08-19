import Foundation

struct UserParameterState: Equatable, Sendable {
  static let vmThresholdDefault: Int32 = 1_048_576

  static let definitions: [String: Definition] = [
    "AccurateScreens": .boolean,
    "HalftoneMode": .integer { min(max($0, 0), 2) },
    "IdiomRecognition": .boolean,
    "JobName": .string(maximumLength: 100),
    "MaxDictStack": .integer { max($0, 3) },
    "MaxExecStack": .nonnegativeInteger,
    "MaxFontItem": .integer { min(max($0, 0), Int32(FontGlyphCache.maximumItemBytes)) },
    "MaxFormItem": .integer { min(max($0, 0), Int32(FormCache.maximumItemBytes)) },
    "MaxLocalVM": .nonnegativeInteger,
    "MaxOpStack": .nonnegativeInteger,
    "MaxPatternItem": .integer { min(max($0, 0), Int32(PatternCache.maximumItemBytes)) },
    "MaxScreenItem": .integer { min(max($0, 0), Int32(ScreenManager.maximumItemBytes)) },
    "MaxSuperScreen": .integer { min(max($0, 0), 1016) },
    "MaxUPathItem": .integer { min(max($0, 0), Int32(UserPathCache.maximumItemBytes)) },
    "MinFontCompress": .nonnegativeInteger,
    "VMReclaim": .integer { min(max($0, -2), 0) },
    "VMThreshold": .integer { $0 == -1 ? vmThresholdDefault : max($0, 0) },
  ]

  static let factoryDefaults: [String: ParameterValue] = [
    "AccurateScreens": .boolean(false),
    "HalftoneMode": .integer(0),
    "IdiomRecognition": .boolean(true),
    "JobName": .string(Data()),
    "MaxDictStack": .integer(.max),
    "MaxExecStack": .integer(.max),
    "MaxFontItem": .integer(Int32(FontGlyphCache.maximumItemBytes)),
    "MaxFormItem": .integer(Int32(FormCache.maximumItemBytes)),
    "MaxLocalVM": .integer(.max),
    "MaxOpStack": .integer(.max),
    "MaxPatternItem": .integer(Int32(PatternCache.maximumItemBytes)),
    "MaxScreenItem": .integer(Int32(ScreenManager.maximumItemBytes)),
    "MaxSuperScreen": .integer(0),
    "MaxUPathItem": .integer(Int32(UserPathCache.maximumItemBytes)),
    "MinFontCompress": .integer(0),
    "VMReclaim": .integer(0),
    "VMThreshold": .integer(vmThresholdDefault),
  ]

  enum Definition: Sendable {
    case boolean
    case integer(@Sendable (Int32) -> Int32)
    case string(maximumLength: Int?)

    static var nonnegativeInteger: Self { .integer { max($0, 0) } }

    func value(from object: Object) throws -> ParameterValue {
      switch self {
      case .boolean:
        try .boolean(from: object)
      case .integer(let normalize):
        .integer(normalize(try ParameterValue.integer(from: object)))
      case .string(let maximumLength):
        try .string(from: object, maximumLength: maximumLength)
      }
    }
  }

  private(set) var values: [String: ParameterValue]

  init(values: [String: ParameterValue] = factoryDefaults) {
    self.values = values
  }

  mutating func update(from dictionary: DictionaryValue) throws {
    try dictionary.access.check(.read)
    var updates: [String: ParameterValue] = [:]
    try dictionary.forEachUnchecked { key, object in
      let name = try PostScriptParameterFailure.wrapping(key: key, value: object) {
        try key.value(as: NameValue.self).value
      }
      guard let definition = Self.definitions[name] else { return }
      updates[name] = try PostScriptParameterFailure.wrapping(key: key, value: object) {
        try definition.value(from: object)
      }
    }
    values.merge(updates) { _, replacement in replacement }
  }

  mutating func merge(_ updates: [String: ParameterValue]) {
    values.merge(updates) { _, replacement in replacement }
  }

  func integer(_ name: String) -> Int32 {
    guard case .integer(let value) = values[name] else {
      preconditionFailure("Missing integer user parameter \(name)")
    }
    return value
  }

  func boolean(_ name: String) -> Bool {
    guard case .boolean(let value) = values[name] else {
      preconditionFailure("Missing boolean user parameter \(name)")
    }
    return value
  }

  mutating func setInteger(_ value: Int32, for name: String) {
    values[name] = .integer(value)
  }
}
