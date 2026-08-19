import Foundation

struct FontResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "Font", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? { FontResourceValidation.instance }
}

enum FontResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    try Operators.validateFontDictionary(dictionary, requiresIdentifier: false, context: context)
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }

  func didDefine(key: Object, instance: Object, context: isolated Context) throws {
    let directory = try context.fontDirectory(for: instance.value(as: DictionaryValue.self).vm)
    try context.updateDictionary(directory, value: instance, forKey: key)
  }

  func willUndefine(key: Object, instance: Object, context: isolated Context) throws {
    let directory = try context.fontDirectory(for: instance.value(as: DictionaryValue.self).vm)
    _ = try directory.removeObject(forKey: key)
  }
}

struct EncodingResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "Encoding", instanceType: .array, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? { EncodingResourceValidation.instance }
}

enum EncodingResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let array = try instance.value(as: ArrayValue.self)
    try array.access.check(.read)
    guard array.count == 256 else { throw Error.rangeCheck }
    for object in try array.objects(in: array.range, for: .read) {
      _ = try object.value(as: NameValue.self)
    }
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}
