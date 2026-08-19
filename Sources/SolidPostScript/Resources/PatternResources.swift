import Foundation

struct PatternResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "Pattern", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    PatternResourceValidation.instance
  }
}

enum PatternResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    let type = try dictionary.objectValue(forKey: "PatternType", as: IntegerValue.self).value
    switch type {
    case 1:
      try Operators.validateTilingPattern(dictionary)
    case 2:
      try Operators.validateShadingDictionaryStructure(
        dictionary.objectValue(forKey: "Shading", as: DictionaryValue.self)
      )
    default:
      throw Error.rangeCheck
    }
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}
