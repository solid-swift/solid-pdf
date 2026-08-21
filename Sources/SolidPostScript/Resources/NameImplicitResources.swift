import Foundation

struct NameImplicitResources: ResourceCategory {
  let category: String
  let values: Set<String>

  var dictionary: ResourceCategoryDictionary {
    .init(category: category, instanceType: .name)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    ImplicitResourceValidation.instance
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    guard let name = key.value as? NameValue, values.contains(name.value) else { return nil }
    return (true, 0)
  }

  func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object {
    guard let name = key.value as? NameValue, values.contains(name.value) else {
      throw Error.undefinedResource
    }
    return .literalName(name.value)
  }

  func sizeOfResource(_ instance: Object) throws -> Int { 0 }

  func enumerateResources(matching template: String) throws -> [Object] {
    guard let regex = template.asTemplateRegex else { return [] }
    return values.sorted().compactMap { name in
      guard (try? regex.wholeMatch(in: name)) != nil else { return nil }
      return .literalName(name)
    }
  }
}
