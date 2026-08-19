import Foundation

struct FontResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "Font", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? { FontResourceValidation.instance }
}

enum FontResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    try Operators.validateFontDictionary(dictionary, requiresIdentifier: false, context: context)
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }

  func didDefine(key: Object, instance: Object, context: isolated Context) throws {
    let directory = try context.fontDirectory(for: instance.value(as: DictionaryValue.self).vm)
    try context.updateDictionary(directory, value: instance, forKey: key)
  }

  func willUndefine(key: Object, instance: Object, context: isolated Context) throws {
    let directory = try context.fontDirectory(for: instance.value(as: DictionaryValue.self).vm)
    _ = try directory.removeObject(forKey: key)
  }
}

struct EncodingResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "Encoding", instanceType: .array, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? { EncodingResourceValidation.instance }
}

struct FontSetResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "FontSet", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? { FontSetResourceValidation.instance }
}

enum FontSetResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    try dictionary.forEachUnchecked { _, font in
      let fontDictionary = try font.value(as: DictionaryValue.self)
      try Operators.validateFontDictionary(fontDictionary, requiresIdentifier: true, context: context)
    }
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}

struct CIDFontResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "CIDFont", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? { CIDFontResourceValidation.instance }
}

enum CIDFontResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    let cidType = try dictionary.objectValue(forKey: "CIDFontType", as: IntegerValue.self).value
    let fontType = try dictionary.objectValue(forKey: "FontType", as: IntegerValue.self).value
    guard [0: 9, 1: 10, 2: 11, 4: 32][cidType] == fontType else { throw Error.invalidFont }
    let count = try dictionary.objectValue(forKey: "CIDCount", as: IntegerValue.self).value
    guard count > 0 else { throw Error.invalidFont }
    try validateCIDSystemInfo(dictionary.object(forKey: "CIDSystemInfo"))
    try Operators.validateFontDictionary(dictionary, requiresIdentifier: false, context: context)
    if cidType == 1 {
      let buildGlyph = try dictionary.object(forKey: "BuildGlyph")
      try buildGlyph.checkProcedure()
    }
    if cidType == 4 {
      let directory = try dictionary.objectValue(forKey: "GlyphDirectory", as: DictionaryValue.self)
      try directory.access.check(.read)
    }
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}

struct CMapResources: ResourceCategory {
  var dictionary: ResourceCategoryDictionary {
    .init(category: "CMap", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? { CMapResourceValidation.instance }
}

enum CMapResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let dictionary = try instance.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    let type = try dictionary.objectValue(forKey: "CMapType", as: IntegerValue.self).value
    guard type == 0 || type == 1 else { throw Error.rangeCheck }
    _ = try dictionary.objectValue(forKey: "CMapName", as: NameValue.self)
    try validateCIDSystemInfo(dictionary.object(forKey: "CIDSystemInfo"))
    let mode = try dictionary.objectValue(forKeyIfExists: "WMode", as: IntegerValue.self)?.value ?? 0
    guard mode == 0 || mode == 1 else { throw Error.rangeCheck }
    let codeMap = try dictionary.objectValue(forKey: "CodeMap", as: DictionaryValue.self)
    try codeMap.access.check(.read)
    let ranges = try dictionary.objectValue(forKey: "CodeSpaceRanges", as: DictionaryValue.self)
    try ranges.access.check(.read)
    guard ranges.count > 0 else { throw Error.rangeCheck }
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}

private func validateCIDSystemInfo(_ object: Object) throws {
  if let array = object.value as? ArrayValue {
    try array.access.check(.read)
    for entry in try array.objects(in: array.range, for: .read) where entry.type != .null {
      try validateCIDSystemInfo(entry)
    }
    return
  }
  let dictionary = try object.value(as: DictionaryValue.self)
  try dictionary.access.check(.read)
  _ = try dictionary.objectValue(forKey: "Registry", as: StringValue.self)
  _ = try dictionary.objectValue(forKey: "Ordering", as: StringValue.self)
  _ = try dictionary.objectValue(forKey: "Supplement", as: IntegerValue.self)
}

enum EncodingResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    let array = try instance.value(as: ArrayValue.self)
    try array.access.check(.read)
    guard array.count == 256 else { throw Error.rangeCheck }
    for object in try array.objects(in: array.range, for: .read) {
      _ = try object.value(as: NameValue.self)
    }
  }

  func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try validateDefinition(key: key, instance: instance, context: context)
  }
}
