//
//  ResourceCategory.swift
//
//
//  Created by Kevin Wooten on 7/9/24.
//

import Foundation

/// A PostScript resource category.
public protocol ResourceCategory: Sendable {

  var dictionary: ResourceCatoryDictionary { get }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)?
  func loadResource(forKey key: Object, in context: isolated Context) throws -> Object
  func sizeOfResource(_ instance: Object) throws -> Int
  func enumerateResources(matching template: String) throws -> [Object]

}

/// A PostScript resource catory dictionary.
public struct ResourceCatoryDictionary: Sendable {
  /// The ``category`` value.
  public var category: String
  /// The ``defineResource`` value.
  public var defineResource: Object
  /// The ``undefineResource`` value.
  public var undefineResource: Object
  /// The ``findResource`` value.
  public var findResource: Object
  /// The ``resourceStatus`` value.
  public var resourceStatus: Object
  /// The ``resourceForAll`` value.
  public var resourceForAll: Object
  /// The ``instanceType`` value.
  public var instanceType: ObjectType?
  /// The ``fileName`` value.
  public var fileName: Object?

  /// Creates an instance.
  public init(
    category: String,
    defineResource: Object = Operators.DefineResource.default,
    undefineResource: Object = Operators.UndefineResource.default,
    findResource: Object = Operators.FindResource.default,
    resourceStatus: Object = Operators.ResourceStatus.default,
    resourceForAll: Object = Operators.ResourceForAll.default,
    instanceType: ObjectType? = nil,
    fileName: Object? = nil
  ) {
    self.category = category
    self.defineResource = defineResource
    self.undefineResource = undefineResource
    self.findResource = findResource
    self.resourceStatus = resourceStatus
    self.resourceForAll = resourceForAll
    self.instanceType = instanceType
    self.fileName = fileName
  }
}
