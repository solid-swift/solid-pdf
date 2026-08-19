import Foundation

struct OutputDeviceResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "OutputDevice", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    TrappingDictionaryResourceValidation.outputDevice
  }
}

struct InkParamsResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "InkParams", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    TrappingDictionaryResourceValidation.inkParameters
  }
}

struct TrapParamsResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "TrapParams", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    TrappingDictionaryResourceValidation.trapParameters
  }
}

enum TrappingDictionaryResourceValidation: Operators.ResourceCategoryExtension {
  case outputDevice
  case inkParameters
  case trapParameters

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    switch self {
    case .outputDevice:
      if let types = try dictionary.object(forKeyIfExists: .literalName("TrappingDetailsType")) {
        _ = try Operators.trappingIntegerArray(types)
      }
    case .inkParameters:
      if let name = try dictionary.object(forKeyIfExists: .literalName("ColorantName")) {
        _ = try name.value(as: NameValue.self)
      }
      if let type = try dictionary.object(forKeyIfExists: .literalName("ColorantType")) {
        let value = try type.value(as: NameValue.self).value
        guard GraphicsTrappingColorantType(rawValue: value) != nil else { throw Error.rangeCheck }
      }
      if let density = try dictionary.object(forKeyIfExists: .literalName("NeutralDensity")) {
        let value = try numeric(density)
        guard (0.001...10).contains(value) else { throw Error.rangeCheck }
      }
    case .trapParameters:
      try Operators.validateTrapParameterDictionary(dictionary)
    }
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }

  private func numeric(_ object: Object) throws -> Double {
    switch object.value {
    case let integer as IntegerValue: Double(integer.value)
    case let real as RealValue: real.value
    default: throw Error.typeCheck
    }
  }
}
