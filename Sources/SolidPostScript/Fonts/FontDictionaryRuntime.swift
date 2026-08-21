import Foundation
import SolidFont

extension Operators {
  struct FontDefinition {
    let object: Object
    let dictionary: DictionaryValue
    let identifier: GraphicsFontIdentifier
    let providerFace: FontProviderFace?
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
    if fontType == 0 {
      let mapType = try dictionary.objectValue(forKey: "FMapType", as: IntegerValue.self).value
      guard standardFMapTypes.contains(mapType) else { throw Error.invalidFont }
      let encoding = try dictionary.objectValue(forKey: "Encoding", as: ArrayValue.self)
      let descendants = try dictionary.objectValue(forKey: "FDepVector", as: ArrayValue.self)
      try encoding.access.check(.read)
      try descendants.access.check(.read)
      guard encoding.count > 0, descendants.count > 0 else { throw Error.invalidFont }
      for entry in try encoding.objects(in: encoding.range, for: .read) {
        _ = try entry.value(as: IntegerValue.self)
      }
      for descendant in try descendants.objects(in: descendants.range, for: .read) {
        _ = try descendant.value(as: DictionaryValue.self)
      }
      let mode = try dictionary.objectValue(forKeyIfExists: "WMode", as: IntegerValue.self)?.value ?? 0
      guard mode == 0 || mode == 1 else { throw Error.invalidFont }
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
    let cidFont = try dictionary.object(forKeyIfExists: "CIDFontType") != nil
    try validateFontDictionary(dictionary, requiresIdentifier: !cidFont, context: context)
    let identifierValue = try dictionary.objectValue(forKeyIfExists: "FID", as: FontIDValue.self)
    guard identifierValue != nil || cidFont else { throw Error.invalidFont }
    let type = try dictionary.objectValue(forKey: "FontType", as: IntegerValue.self).value
    let matrix = try readMatrix(dictionary.object(forKey: "FontMatrix"))
    let fontName = try dictionary.objectValue(forKeyIfExists: "FontName", as: NameValue.self)?.value
      ?? dictionary.objectValue(forKeyIfExists: "CIDFontName", as: NameValue.self)?.value
    let identifier = identifierValue?.identifier
      ?? GraphicsFontIdentifier("CID:\(dictionary.allocation.identity.hashValue)")
    let paintType = Int(try dictionary.objectValue(forKeyIfExists: "PaintType", as: IntegerValue.self)?.value ?? 0)
    let strokeWidth = try dictionary.object(forKeyIfExists: "StrokeWidth").map(numeric) ?? 0
    let description = GraphicsFontDescription(
      identifier: identifier,
      resourceName: fontName,
      postScriptName: identifierValue?.providerFace?.asset.descriptor.postScriptName ?? fontName,
      matrix: matrix,
      writingMode: Int(try dictionary.objectValue(forKeyIfExists: "WMode", as: IntegerValue.self)?.value ?? 0),
      asset: identifierValue?.providerFace?.asset,
      outlineAccess: identifierValue?.providerFace?.asset.descriptor.outlineAccess ?? .extractable,
      technology: fontTechnology(type),
      fontType: Int(type),
      paintType: paintType,
      strokeWidth: strokeWidth,
      resourceIdentifier: GraphicsResourceIdentifier(rawValue: "font:\(identifier.value)")
    )
    return FontDefinition(
      object: object,
      dictionary: dictionary,
      identifier: identifier,
      providerFace: identifierValue?.providerFace,
      type: type,
      matrix: matrix,
      description: description
    )
  }

  private static func fontTechnology(_ fontType: Int32) -> GraphicsFontTechnology {
    switch fontType {
    case 0: .composite
    case 1: .type1
    case 2: .compactFontFormat
    case 3: .type3
    case 9: .cidType0
    case 10: .cidType1
    case 11: .cidType2
    case 14: .chameleon
    case 32: .bitmap
    case 42: .trueType
    default: .unknown
    }
  }

  static func initializeFont(
    _ object: Object,
    resourceName: String?,
    providerFace: FontProviderFace? = nil,
    propagateCompositeMatrix: Bool = true,
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

    if try dictionary.objectValue(forKey: "FontType", as: IntegerValue.self).value == 0 {
      let matrix = try readMatrix(dictionary.object(forKey: "FontMatrix"))
      if propagateCompositeMatrix, matrix != .identity {
        try replaceCompositeDescendants(in: dictionary, applying: matrix, context: context)
      }
      let mapType = try dictionary.objectValue(forKey: "FMapType", as: IntegerValue.self).value
      if (mapType == 3 || mapType == 7), try dictionary.object(forKeyIfExists: "EscChar") == nil {
        try context.updateDictionary(dictionary, value: .integer(255), forKey: "EscChar")
      }
      if mapType == 8 {
        if try dictionary.object(forKeyIfExists: "ShiftOut") == nil {
          try context.updateDictionary(dictionary, value: .integer(14), forKey: "ShiftOut")
        }
        if try dictionary.object(forKeyIfExists: "ShiftIn") == nil {
          try context.updateDictionary(dictionary, value: .integer(15), forKey: "ShiftIn")
        }
      }
    }

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

  static func deriveFont(
    _ fontObject: Object,
    matrix: GraphicsMatrix,
    vm: VM,
    context: isolated Context
  ) throws -> Object {
    let savedMode = context.allocationMode
    context.allocationMode = vm
    defer { context.allocationMode = savedMode }
    let source = try fontDefinition(fontObject, context: context)
    var entries: [(Object, Object)] = []
    try source.dictionary.forEachUnchecked { key, value in
      if key != "FID", key != "FontMatrix", key != "FDepVector" { entries.append((key, value)) }
    }
    entries.append((.literalName("FontMatrix"), try makeMatrixObject(
      source.matrix.concatenated(with: matrix), context: context
    )))
    if source.type == 0 {
      let vector = try source.dictionary.objectValue(forKey: "FDepVector", as: ArrayValue.self)
      let descendants = try vector.objects(in: vector.range, for: .read).map { descendant -> Object in
        let definition = try fontDefinition(descendant, context: context)
        return definition.type == 0
          ? try deriveFont(descendant, matrix: matrix, vm: vm, context: context)
          : descendant
      }
      let derivedVector = try Object.array(descendants, access: .readOnly, vm: vm, kind: .literal)
      try context.adopt(derivedVector)
      entries.append((.literalName("FDepVector"), derivedVector))
    }
    let dictionary = try context.makeDictionary(entries, access: .unlimited, vm: vm)
    return try initializeFont(
      dictionary,
      resourceName: source.description.resourceName,
      providerFace: source.providerFace,
      propagateCompositeMatrix: false,
      context: context
    )
  }

  private static func replaceCompositeDescendants(
    in dictionary: DictionaryValue,
    applying matrix: GraphicsMatrix,
    context: isolated Context
  ) throws {
    let vector = try dictionary.objectValue(forKey: "FDepVector", as: ArrayValue.self)
    let descendants = try vector.objects(in: vector.range, for: .read).map { descendant -> Object in
      let definition = try fontDefinition(descendant, context: context)
      return definition.type == 0
        ? try deriveFont(descendant, matrix: matrix, vm: dictionary.vm, context: context)
        : descendant
    }
    let normalized = try Object.array(descendants, access: .readOnly, vm: dictionary.vm, kind: .literal)
    try context.adopt(normalized)
    try context.updateDictionary(dictionary, value: normalized, forKey: "FDepVector")
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

  static func embeddedProviderFace(
    for dictionary: DictionaryValue,
    resourceName: String,
    context: isolated Context
  ) async throws -> FontProviderFace? {
    let fontType = try dictionary.objectValue(forKey: "FontType", as: IntegerValue.self).value
    guard fontType == 42 || fontType == 11 else { return nil }
    _ = try dictionary.objectValue(forKey: "CharStrings", as: DictionaryValue.self)
    let fragments = try arrayObjects(dictionary.object(forKey: "sfnts"))
    guard !fragments.isEmpty else { throw Error.invalidFont }
    var data = Data()
    for fragment in fragments {
      let string = try fragment.value(as: StringValue.self)
      data.append(try string.characters(in: string.range))
    }
    let collection: SFNTCollection
    do {
      collection = try SFNTCollection(data: data)
    } catch {
      throw Error.invalidFont
    }
    let requestedName = try dictionary.objectValue(forKeyIfExists: "FontName", as: NameValue.self)?.value
      ?? dictionary.objectValue(forKeyIfExists: "CIDFontName", as: NameValue.self)?.value
      ?? resourceName
    let providers = context.environment.fontProviders.filter { $0.supportedAssetFormats.contains(.sfnt) }
    guard !providers.isEmpty else { throw Error.invalidFont }
    for provider in providers {
      for faceIndex in collection.faces.indices {
        let descriptor: FontDescriptor
        let asset: FontAsset
        do {
          descriptor = try FontDescriptor(postScriptName: requestedName, unitsPerEm: 1_000)
          asset = try FontAsset(
            descriptor: descriptor,
            format: .sfnt,
            data: data,
            faceIndex: faceIndex
          )
        } catch {
          throw Error.invalidFont
        }
        let opened = try await context.withUserTimeSuspended { try await provider.open(asset) }
        if let opened, opened.asset.descriptor.postScriptName == requestedName { return opened }
      }
    }
    throw Error.invalidFont
  }

  static func decodeDictionaryGlyph(
    selector: GraphicsGlyphSelector,
    font: FontDefinition
  ) throws -> GraphicsGlyphDescription {
    try decodeDictionaryGlyph(selector: selector, font: font, compositeDepth: 0)
  }

  static func dictionaryGlyphProcedure(
    selector: GraphicsGlyphSelector,
    font: FontDefinition
  ) throws -> Object? {
    guard font.type == 1 || font.type == 2 || font.type == 9 else { return nil }
    let charStrings = try font.dictionary.objectValue(forKey: "CharStrings", as: DictionaryValue.self)
    try charStrings.access.check(.read)
    let keys: [Object]
    switch selector {
    case .name(let name): keys = [.literalName(name), .literalName(".notdef")]
    case .cid(let cid) where cid <= UInt32(Int32.max): keys = [.integer(Int32(cid)), .integer(0)]
    default: return nil
    }
    for key in keys {
      guard let entry = try charStrings.object(forKeyIfExists: key) else { continue }
      if entry.isProcedure { return entry }
      return Optional<Object>.none
    }
    return nil
  }

  private static func decodeDictionaryGlyph(
    selector: GraphicsGlyphSelector,
    font: FontDefinition,
    compositeDepth: Int
  ) throws -> GraphicsGlyphDescription {
    guard compositeDepth <= FontParsingLimits.default.maximumSubroutineDepth else { throw Error.limitCheck }
    if font.type == 32 { return try decodeBitmapGlyph(selector: selector, font: font) }
    guard font.type == 1 || font.type == 2 || font.type == 9 else {
      return .missing(selector)
    }
    let charStrings = try font.dictionary.objectValue(forKey: "CharStrings", as: DictionaryValue.self)
    try charStrings.access.check(.read)
    let key: Object
    let fallback: Object
    switch selector {
    case .name(let name):
      key = .literalName(name)
      fallback = .literalName(".notdef")
    case .cid(let cid):
      guard cid <= UInt32(Int32.max) else { return .missing(selector) }
      key = .integer(Int32(cid))
      fallback = .integer(0)
    default:
      return .missing(selector)
    }
    let charStringObject = try charStrings.object(forKeyIfExists: key)
      ?? charStrings.object(forKeyIfExists: fallback)
    guard let charStringObject else { return .missing(selector) }
    let string = try charStringObject.value(as: StringValue.self)
    var data = try string.characters(in: string.range)
    var localSubroutines: [Data] = []
    var globalSubroutines: [Data] = []
    var defaultWidth = 0.0
    var nominalWidth = 0.0
    if let privateDictionary = try font.dictionary.objectValue(forKeyIfExists: "Private", as: DictionaryValue.self) {
      if let subrs = try privateDictionary.objectValue(forKeyIfExists: "Subrs", as: ArrayValue.self) {
        localSubroutines = try subrs.objects(in: subrs.range, for: .read).map {
          let value = try $0.value(as: StringValue.self)
          return try value.characters(in: value.range)
        }
      }
      if let subrs = try privateDictionary.objectValue(forKeyIfExists: "GlobalSubrs", as: ArrayValue.self) {
        globalSubroutines = try subrs.objects(in: subrs.range, for: .read).map {
          let value = try $0.value(as: StringValue.self)
          return try value.characters(in: value.range)
        }
      }
      if let value = try privateDictionary.object(forKeyIfExists: "defaultWidthX") {
        defaultWidth = try numeric(value)
      }
      if let value = try privateDictionary.object(forKeyIfExists: "nominalWidthX") {
        nominalWidth = try numeric(value)
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
      dialect: font.type == 1 || font.type == 9 ? .type1 : .type2,
      localSubroutines: localSubroutines,
      globalSubroutines: globalSubroutines,
      defaultWidth: defaultWidth,
      nominalWidth: nominalWidth
    )
    var outline = GraphicsPath(decoded.outline)
    for component in decoded.components {
      let glyph = try decodeDictionaryGlyph(
        selector: .name(StandardEncodings.standardName(for: component.characterCode)),
        font: font,
        compositeDepth: compositeDepth + 1
      )
      guard case .outline(let componentPath) = glyph.program else { continue }
      let translated = componentPath.transformed(by: GraphicsMatrix(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        tx: component.offset.x,
        ty: component.offset.y
      ))
      let count = outline.elements.count.addingReportingOverflow(translated.elements.count)
      guard !count.overflow, count.partialValue <= FontParsingLimits.default.maximumOutlineElements else {
        throw Error.limitCheck
      }
      outline = GraphicsPath(elements: outline.elements + translated.elements)
    }
    return GraphicsGlyphDescription(
      selector: selector,
      metrics: GraphicsGlyphMetrics(
        horizontalAdvance: GraphicsPoint(x: decoded.advance.x, y: decoded.advance.y)
      ),
      program: .outline(outline)
    )
  }

  private static func decodeBitmapGlyph(
    selector: GraphicsGlyphSelector,
    font: FontDefinition
  ) throws -> GraphicsGlyphDescription {
    guard case .cid(let cid) = selector, cid <= UInt32(Int32.max) else { return .missing(selector) }
    let directory = try font.dictionary.objectValue(forKey: "GlyphDirectory", as: DictionaryValue.self)
    guard let entry = try directory.object(forKeyIfExists: .integer(Int32(cid)))
      ?? directory.object(forKeyIfExists: .integer(0))
    else { return .missing(selector) }
    let glyph = try entry.value(as: DictionaryValue.self)
    let width = try glyph.objectValue(forKey: "Width", as: IntegerValue.self).value
    let height = try glyph.objectValue(forKey: "Height", as: IntegerValue.self).value
    let data = try glyph.objectValue(forKey: "Data", as: StringValue.self)
    let bytes = try data.characters(in: data.range)
    guard width >= 0, height >= 0 else { throw Error.invalidFont }
    let rowBytes = (Int(width) + 7) / 8
    guard bytes.count == rowBytes * Int(height) else { throw Error.invalidFont }
    var coverage = Data(count: Int(width) * Int(height))
    for row in 0..<Int(height) {
      for column in 0..<Int(width) {
        coverage[row * Int(width) + column] = bytes[row * rowBytes + column / 8] & (0x80 >> (column % 8)) == 0
          ? 0 : 255
      }
    }
    let advance = try glyph.objectValue(forKeyIfExists: "Advance", as: IntegerValue.self)?.value ?? width
    return GraphicsGlyphDescription(
      selector: selector,
      metrics: GraphicsGlyphMetrics(horizontalAdvance: GraphicsPoint(x: Double(advance), y: 0)),
      program: .bitmap(try FontGlyphBitmap(
        width: Int(width), height: Int(height), bytesPerRow: Int(width), originX: 0, originY: Int(height), coverage: coverage
      ))
    )
  }
}
