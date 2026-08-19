import Foundation
import SolidFont

extension Operators {
  struct FontDefinition {
    let object: Object
    let dictionary: DictionaryValue
    let identifier: FontIDValue
    let type: Int32
    let matrix: GraphicsMatrix
    let description: GraphicsFontDescription
  }

  static func validateFontDictionary(
    _ dictionary: DictionaryValue,
    requiresIdentifier: Bool,
    context: isolated Context
  ) throws {
    try dictionary.access.check(.read)
    let fontType = try dictionary.objectValue(forKey: "FontType", as: IntegerValue.self).value
    guard [0, 1, 2, 3, 9, 10, 11, 14, 32, 42].contains(fontType) else { throw Error.invalidFont }
    if fontType == 14, !context.environment.fontProviders.contains(where: { $0.supportsChameleonFonts }) {
      throw Error.invalidFont
    }
    _ = try readMatrix(dictionary.object(forKey: "FontMatrix"))
    let bounds = try numericArray(dictionary.object(forKey: "FontBBox"), count: 4)
    guard bounds.allSatisfy(\.isFinite) else { throw Error.invalidFont }
    if let name = try dictionary.object(forKeyIfExists: "FontName") {
      _ = try name.value(as: NameValue.self)
    }
    if fontType == 3 {
      let buildGlyph = try dictionary.object(forKeyIfExists: "BuildGlyph")
      let buildChar = try dictionary.object(forKeyIfExists: "BuildChar")
      guard buildGlyph != nil || buildChar != nil else { throw Error.invalidFont }
      try buildGlyph?.checkProcedure()
      try buildChar?.checkProcedure()
    }
    if [1, 2, 3, 14, 42].contains(fontType) {
      let encoding = try dictionary.objectValue(forKey: "Encoding", as: ArrayValue.self)
      try encoding.access.check(.read)
      guard encoding.count == 256 else { throw Error.invalidFont }
    }
    if requiresIdentifier {
      _ = try dictionary.objectValue(forKey: "FID", as: FontIDValue.self)
    }
  }

  static func fontDefinition(_ object: Object, context: isolated Context) throws -> FontDefinition {
    let dictionary = try object.value(as: DictionaryValue.self)
    try validateFontDictionary(dictionary, requiresIdentifier: true, context: context)
    let identifier = try dictionary.objectValue(forKey: "FID", as: FontIDValue.self)
    let type = try dictionary.objectValue(forKey: "FontType", as: IntegerValue.self).value
    let matrix = try readMatrix(dictionary.object(forKey: "FontMatrix"))
    let fontName = try dictionary.objectValue(forKeyIfExists: "FontName", as: NameValue.self)?.value
    let description = GraphicsFontDescription(
      identifier: identifier.identifier,
      resourceName: fontName,
      postScriptName: identifier.providerFace?.asset.descriptor.postScriptName ?? fontName,
      matrix: matrix,
      asset: identifier.providerFace?.asset
    )
    return FontDefinition(
      object: object,
      dictionary: dictionary,
      identifier: identifier,
      type: type,
      matrix: matrix,
      description: description
    )
  }

  static func initializeFont(
    _ object: Object,
    resourceName: String?,
    providerFace: FontProviderFace? = nil,
    context: isolated Context
  ) throws -> Object {
    let dictionary = try object.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    if let existing = try dictionary.objectValue(forKeyIfExists: "FID", as: FontIDValue.self) {
      _ = existing
      try validateFontDictionary(dictionary, requiresIdentifier: true, context: context)
      return object
    }
    try dictionary.access.check(.write)
    try validateFontDictionary(dictionary, requiresIdentifier: false, context: context)

    let identifier = GraphicsFontIdentifier(UUID().uuidString)
    let fid = Object.fontID(identifier: identifier, providerFace: providerFace, vm: dictionary.vm)
    try context.preflightAllocation(bytes: 32, vm: dictionary.vm)
    try context.adopt(fid)
    try context.updateDictionary(dictionary, value: fid, forKey: "FID")
    if let resourceName, try dictionary.object(forKeyIfExists: "FontName") == nil {
      try context.updateDictionary(dictionary, value: .literalName(resourceName), forKey: "FontName")
    }
    try dictionary.setAccess(to: .readOnly)
    return object
  }

  static func makeProviderFont(
    _ face: FontProviderFace,
    requestedName: String,
    context: isolated Context
  ) throws -> Object {
    let fontType: Int32 = switch face.asset.format {
    case .type1: 1
    case .compactFontFormat: 2
    case .type3: 3
    case .chameleon: 14
    case .sfnt: 42
    }
    let previousMode = context.allocationMode
    context.allocationMode = .global
    defer { context.allocationMode = previousMode }
    let matrix = try makeMatrixObject(
      GraphicsMatrix(a: 0.001, b: 0, c: 0, d: 0.001, tx: 0, ty: 0),
      context: context
    )
    let bounds = try Object.array(
      [0, 0, 0, 0], access: .readOnly, vm: .global, kind: .literal
    )
    try context.adopt(bounds)
    let dictionary = try context.makeDictionary([
      (.literalName("FontType"), .integer(fontType)),
      (.literalName("FontName"), .literalName(face.asset.descriptor.postScriptName)),
      (.literalName("FontMatrix"), matrix),
      (.literalName("FontBBox"), bounds),
      (.literalName("Encoding"), context.environment.standardEncoding),
    ], access: .unlimited, vm: .global)
    return try initializeFont(
      dictionary,
      resourceName: requestedName,
      providerFace: face,
      context: context
    )
  }

  static func decodeDictionaryGlyph(
    selector: GraphicsGlyphSelector,
    font: FontDefinition
  ) throws -> GraphicsGlyphDescription {
    guard font.type == 1 || font.type == 2 else {
      return .missing(selector)
    }
    let glyphName: String
    switch selector {
    case .name(let name): glyphName = name
    default: return .missing(selector)
    }
    let charStrings = try font.dictionary.objectValue(forKey: "CharStrings", as: DictionaryValue.self)
    try charStrings.access.check(.read)
    let charStringObject = try charStrings.object(forKeyIfExists: .literalName(glyphName))
      ?? charStrings.object(forKeyIfExists: .literalName(".notdef"))
    guard let charStringObject else { return .missing(selector) }
    let string = try charStringObject.value(as: StringValue.self)
    var data = try string.characters(in: string.range)
    var localSubroutines: [Data] = []
    if let privateDictionary = try font.dictionary.objectValue(forKeyIfExists: "Private", as: DictionaryValue.self) {
      if let subrs = try privateDictionary.objectValue(forKeyIfExists: "Subrs", as: ArrayValue.self) {
        localSubroutines = try subrs.objects(in: subrs.range, for: .read).map {
          let value = try $0.value(as: StringValue.self)
          return try value.characters(in: value.range)
        }
      }
      if font.type == 1 {
        let lenIV = try privateDictionary.objectValue(forKeyIfExists: "lenIV", as: IntegerValue.self)?.value ?? 4
        data = try FontCharStringDecoder.decryptType1(data, lenIV: Int(lenIV))
        localSubroutines = try localSubroutines.map {
          try FontCharStringDecoder.decryptType1($0, lenIV: Int(lenIV))
        }
      }
    }
    let decoded = try FontCharStringDecoder.decode(
      data,
      dialect: font.type == 1 ? .type1 : .type2,
      localSubroutines: localSubroutines
    )
    return GraphicsGlyphDescription(
      selector: selector,
      metrics: GraphicsGlyphMetrics(
        horizontalAdvance: GraphicsPoint(x: decoded.advance.x, y: decoded.advance.y)
      ),
      program: .outline(GraphicsPath(decoded.outline))
    )
  }
}
