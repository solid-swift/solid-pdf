import Foundation

struct HalftoneResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "Halftone", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    HalftoneResourceValidation.instance
  }
}

enum HalftoneResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    try Operators.validateHalftoneDictionaryStructure(instance.value(as: DictionaryValue.self))
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}
