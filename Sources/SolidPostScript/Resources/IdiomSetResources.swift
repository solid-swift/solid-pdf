//
//  IdiomSetResources.swift
//  SolidPostScript
//

import Foundation

enum IdiomSetResources: ResourceCategory {
  case instance

  var dictionary: ResourceCatoryDictionary {
    .init(category: "IdiomSet", instanceType: .dictionary)
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    nil
  }

  func loadResource(forKey key: Object, in context: isolated Context) throws -> Object {
    throw Error.undefinedResource
  }

  func sizeOfResource(_ instance: Object) throws -> Int {
    -1
  }

  func enumerateResources(matching template: String) throws -> [Object] {
    []
  }
}

enum IdiomSetValidation: Operators.ResourceCategoryExtension {
  case instance

  func execute(context: isolated Context, instances: some Collection<Object>) throws {
    for instance in instances {
      guard let dictionary = instance.value as? DictionaryValue else { throw Error.typeCheck }
      try dictionary.forEachUnchecked { _, value in
        guard let pair = value.value as? any CollectionValue, pair.count == 2 else {
          throw Error.typeCheck
        }
        let procedures = try pair.objects(in: pair.range)
        guard procedures.allSatisfy({ $0.kind == .executable && $0.value is any CollectionValue }) else {
          throw Error.typeCheck
        }
      }
    }
  }
}
