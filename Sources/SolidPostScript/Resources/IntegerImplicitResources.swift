import Foundation

struct IntegerImplicitResources: ResourceCategory {
  let category: String
  let values: Set<Int32>

  var dictionary: ResourceCategoryDictionary {
    .init(category: category, instanceType: .integer)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    ImplicitResourceValidation.instance
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    guard let integer = key.value as? IntegerValue, values.contains(integer.value) else { return nil }
    return (true, 0)
  }

  func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object {
    guard try statusOfResource(forKey: key) != nil else { throw Error.undefinedResource }
    return key
  }

  func sizeOfResource(_ instance: Object) throws -> Int { 0 }

  func enumerateResources(matching template: String) throws -> [Object] {
    values.sorted().map(Object.integer)
  }
}
