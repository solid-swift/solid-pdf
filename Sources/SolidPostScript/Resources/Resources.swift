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

  /// The standard LanguageLevel 3 resource-category providers.
  public static let resources: [Object: any ResourceCategory] = [
    "Font": StandardResourceCategory(category: "Font", instanceType: .dictionary),
    "CIDFont": StandardResourceCategory(category: "CIDFont", instanceType: .dictionary),
    "CMap": StandardResourceCategory(category: "CMap", instanceType: .dictionary),
    "FontSet": StandardResourceCategory(category: "FontSet", instanceType: .dictionary),
    "Encoding": StandardResourceCategory(category: "Encoding", instanceType: .array),
    "Form": StandardResourceCategory(category: "Form", instanceType: .dictionary),
    "Pattern": StandardResourceCategory(category: "Pattern", instanceType: .dictionary),
    "ProcSet": ProcSetResources(),
    "ColorSpace": StandardResourceCategory(category: "ColorSpace", instanceType: .array),
    "Halftone": StandardResourceCategory(category: "Halftone", instanceType: .dictionary),
    "ColorRendering": StandardResourceCategory(category: "ColorRendering", instanceType: .dictionary),
    "IdiomSet": IdiomSetResources.instance,
    "InkParams": StandardResourceCategory(category: "InkParams", instanceType: .dictionary),
    "TrapParams": StandardResourceCategory(category: "TrapParams", instanceType: .dictionary),
    "OutputDevice": StandardResourceCategory(category: "OutputDevice", instanceType: .dictionary),
    "ControlLanguage": StandardResourceCategory(category: "ControlLanguage", instanceType: .dictionary),
    "Localization": StandardResourceCategory(category: "Localization", instanceType: .dictionary),
    "PDL": StandardResourceCategory(category: "PDL", instanceType: .dictionary),
    "HWOptions": StandardResourceCategory(category: "HWOptions", instanceType: .dictionary),
    "Filter": FilterResources.instance,
    "ColorSpaceFamily": ImplicitResourceCategory(category: "ColorSpaceFamily", instanceType: .name),
    "Emulator": ImplicitResourceCategory(category: "Emulator", instanceType: .name),
    "IODevice": IODeviceResources.instance,
    "ColorRenderingType": ImplicitResourceCategory(category: "ColorRenderingType", instanceType: .integer),
    "FMapType": ImplicitResourceCategory(category: "FMapType", instanceType: .integer),
    "FontType": ImplicitResourceCategory(category: "FontType", instanceType: .integer),
    "FormType": ImplicitResourceCategory(category: "FormType", instanceType: .integer),
    "HalftoneType": ImplicitResourceCategory(category: "HalftoneType", instanceType: .integer),
    "ImageType": ImplicitResourceCategory(category: "ImageType", instanceType: .integer),
    "PatternType": ImplicitResourceCategory(category: "PatternType", instanceType: .integer),
    "FunctionType": ImplicitResourceCategory(category: "FunctionType", instanceType: .integer),
    "ShadingType": ImplicitResourceCategory(category: "ShadingType", instanceType: .integer),
    "TrappingType": ImplicitResourceCategory(category: "TrappingType", instanceType: .integer),
    "Category": CategoryResources.instance,
  ]

  /// Performs the ``loadCategory`` operation.
  public static func loadCategory(forKey key: Object) throws -> any ResourceCategory {
    guard let resourceCategory = resources[try canonicalResourceKey(key)] else {
      throw Error.undefined
    }

    return resourceCategory
  }

  /// Performs the ``loadInstance`` operation.
  public static func loadInstance(forKey key: Object, in categoryKey: Object, context: isolated Context) async throws
    -> Object
  {
    guard let resourceCategory = try context.environment.resourceCategory(for: categoryKey) else {
      throw Error.undefined
    }
    return try await context.loadResource(from: resourceCategory, forKey: key)
  }

}

private struct StandardResourceCategory: ResourceCategory {
  let category: String
  let instanceType: ObjectType

  var dictionary: ResourceCategoryDictionary {
    .init(category: category, instanceType: instanceType, fileName: Operators.ResourceFileName.default)
  }
}

private struct ImplicitResourceCategory: ResourceCategory {
  let category: String
  let instanceType: ObjectType

  var dictionary: ResourceCategoryDictionary {
    .init(category: category, instanceType: instanceType)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    ImplicitResourceValidation.instance
  }
}
