//
//  FilterResources.swift
//  SolidPostScript
//
//  Created by Codex on 8/15/26.
//

import Foundation

enum FilterResources: ResourceCategory {
  case instance

  var dictionary: ResourceCategoryDictionary {
    .init(category: "Filter", instanceType: .name)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    ImplicitResourceValidation.instance
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    guard let name = key.value as? NameValue,
          Operators.Filter.availableNames.contains(name.value)
    else {
      return nil
    }
    return (true, 0)
  }

  func loadResource(forKey key: Object, in context: isolated Context) throws -> Object {
    guard try statusOfResource(forKey: key) != nil else { throw Error.undefinedResource }
    return key
  }

  func sizeOfResource(_ instance: Object) throws -> Int {
    0
  }

  func enumerateResources(matching template: String) throws -> [Object] {
    guard let regex = template.asTemplateRegex else { return [] }
    return Operators.Filter.availableNames.compactMap { name in
      guard (try? regex.wholeMatch(in: name)) != nil else { return nil }
      return .literalName(name)
    }
  }

}
