//
//  CategoryResources.swift
//
//
//  Created by Kevin Wooten on 7/10/24.
//

import Foundation

/// A PostScript category resources.
public enum CategoryResources: ResourceCategory {

  /// The ``dictionary`` value.
  public var dictionary: ResourceCatoryDictionary {
    .init(category: "Generic")
  }

  /// Performs the ``statusOfResource`` operation.
  public func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    return nil
  }

  /// Performs the ``loadResource`` operation.
  public func loadResource(forKey key: Object, in context: isolated Context) throws -> Object {
    throw Error.undefinedResource
  }

  /// Performs the ``sizeOfResource`` operation.
  public func sizeOfResource(_ instance: Object) throws -> Int {
    return -1
  }

  /// Performs the ``enumerateResources`` operation.
  public func enumerateResources(matching template: String) throws -> [Object] {
    return []
  }

}
