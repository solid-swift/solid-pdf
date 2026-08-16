//
//  ResourceCategory.swift
//
//
//  Created by Kevin Wooten on 7/9/24.
//

import Foundation

/// A PostScript resource category.
public protocol ResourceCategory: Sendable {

  /// The global implementation dictionary installed in the `Category` category.
  var dictionary: ResourceCategoryDictionary { get }

  /// Category-specific validation and lifecycle behavior.
  var resourceExtension: (any Operators.ResourceCategoryExtension)? { get }

  /// Reports whether a provider can supply a resource and its known VM size.
  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)?
  /// Loads a provider-backed resource instance.
  func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object
  /// Reports the instance's known VM size, or `-1` when it is unknown.
  func sizeOfResource(_ instance: Object) throws -> Int
  /// Enumerates provider-backed resource keys matching a PLRM wildcard template.
  func enumerateResources(matching template: String) throws -> [Object]

}

extension ResourceCategory {
  /// Categories without special semantics use the generic implementation.
  public var resourceExtension: (any Operators.ResourceCategoryExtension)? { nil }

  /// Categories without an external provider have no externally available instances.
  public func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? { nil }

  /// Categories without an external provider cannot load an instance.
  public func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object {
    throw Error.undefinedResource
  }

  /// The VM consumption of an explicitly defined resource is generally unknown.
  public func sizeOfResource(_ instance: Object) throws -> Int { -1 }

  /// Categories without an external provider enumerate no external instances.
  public func enumerateResources(matching template: String) throws -> [Object] { [] }
}

/// A PostScript resource category implementation dictionary.
public struct ResourceCategoryDictionary: Sendable {
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

  func object() throws -> Object {
    var entries: [Object: Object] = [
      "Category": .literalName(category),
      "DefineResource": defineResource,
      "UndefineResource": undefineResource,
      "FindResource": findResource,
      "ResourceStatus": resourceStatus,
      "ResourceForAll": resourceForAll,
    ]
    if let instanceType {
      entries["InstanceType"] = .literalName(instanceType.name)
    }
    if let fileName {
      entries["ResourceFileName"] = fileName
    }

    let object = try Object.dictionary(entries, access: .unlimited, vm: .global, kind: .literal)
    try object.value(as: DictionaryValue.self).setAccess(to: .readOnly)
    return object
  }
}

/// Compatibility spelling for ``ResourceCategoryDictionary``.
@available(*, deprecated, renamed: "ResourceCategoryDictionary")
public typealias ResourceCatoryDictionary = ResourceCategoryDictionary
