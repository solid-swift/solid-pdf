import Foundation

struct FormResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "Form", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    FormResourceValidation.instance
  }
}

enum FormResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    try Operators.validateFormDictionary(dictionary)
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}
