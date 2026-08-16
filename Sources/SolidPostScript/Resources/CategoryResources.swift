//
//  CategoryResources.swift
//
//
//  Created by Kevin Wooten on 7/10/24.
//

import Foundation

/// A PostScript category resources.
public enum CategoryResources: ResourceCategory {
  case instance

  /// The ``dictionary`` value.
  public var dictionary: ResourceCategoryDictionary {
    .init(
      category: "Category",
      instanceType: .dictionary,
      fileName: Operators.ResourceFileName.default
    )
  }

  /// Category definitions require their own structural validation.
  public var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    CategoryResourceValidation.instance
  }

}
