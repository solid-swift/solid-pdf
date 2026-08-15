//
//  Resources.swift
//
//
//  Created by Kevin Wooten on 7/9/24.
//

import Foundation

/// A PostScript resources.
public enum Resources {
  case instance

  /// The ``resources`` value.
  public static let resources: [Object: any ResourceCategory] = [:]

  /// Performs the ``loadCategory`` operation.
  public static func loadCategory(forKey key: Object) throws -> any ResourceCategory {

    guard let resourceCategory = resources[key] else {
      throw Error.undefined
    }

    return resourceCategory
  }

  /// Performs the ``loadInstance`` operation.
  public static func loadInstance(forKey key: Object, in categoryKey: Object, context: isolated Context) throws
    -> Object
  {

    let resourceCategory = try loadCategory(forKey: key)

    return try resourceCategory.loadResource(forKey: key, in: context)
  }

}
