//
//  IdiomSetResources.swift
//  SolidPostScript
//

import Foundation

enum IdiomSetResources: ResourceCategory {
  case instance

  var dictionary: ResourceCategoryDictionary {
    .init(category: "IdiomSet", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    IdiomSetValidation.instance
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    nil
  }

  func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object {
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

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    try validate(instance)
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validate(instance)
  }

  private func validate(_ instance: Object) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.forEachUnchecked { _, value in
      guard let pair = value.value as? ArrayValue, pair.count == 2 else {
        throw Error.typeCheck
      }
      let procedures = try pair.objects(in: pair.range)
      for procedure in procedures {
        try procedure.checkProcedure()
      }
    }
  }
}
