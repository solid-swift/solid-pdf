//
//  IODeviceResources.swift
//  SolidPostScript
//

import Foundation

enum IODeviceResources: ResourceCategory {
  case instance

  var dictionary: ResourceCatoryDictionary {
    .init(category: "IODevice", instanceType: .string)
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
