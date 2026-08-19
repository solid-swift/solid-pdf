import Foundation

extension Operators {
  static let fontOps: [OperatorValue] = [
    DefineFont.instance,
    UndefineFont.instance,
    FindFont.instance,
    MakeFont.instance,
    ScaleFont.instance,
    SelectFont.instance,
    SetFont.instance,
    CurrentFont.instance,
    RootFont.instance,
    FindEncoding.instance,
    ComposeFont.instance,
    CacheStatus.instance,
    SetCacheLimit.instance,
    SetCacheParams.instance,
    CurrentCacheParams.instance,
  ]

  enum DefineFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["definefont"]

    func execute(context: isolated Context) async throws {
      let (dictionaryObject, keyObject) = try context.operands.pop2()
      let key = try canonicalResourceKey(keyObject)
      let name = try key.value(as: NameValue.self).value
      let dictionary = try dictionaryObject.value(as: DictionaryValue.self)
      let initialized = try initializeFont(dictionaryObject, resourceName: name, context: context)
      let savedMode = context.allocationMode
      context.allocationMode = dictionary.vm
      defer { context.allocationMode = savedMode }
      context.operands.push(
        try await ResourceRuntime.define(
          initialized,
          for: key,
          in: .literalName("Font"),
          origin: .explicit,
          context: context
        )
      )
    }
  }

  enum UndefineFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["undefinefont"]

    func execute(context: isolated Context) async throws {
      let key = try canonicalResourceKey(context.operands.pop())
      try await ResourceRuntime.remove(key, from: .literalName("Font"), context: context)
    }
  }

  enum FindFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["findfont"]

    func execute(context: isolated Context) async throws {
      let key = try canonicalResourceKey(context.operands.pop())
      do {
        context.operands.push(try await ResourceRuntime.find(key, in: .literalName("Font"), context: context))
        return
      } catch Error.undefinedResource {
      }

      let requested = try key.value(as: NameValue.self).value
      guard let face = try await resolveProviderFace(requested, context: context) else {
        throw Error.invalidFont
      }
      let font = try makeProviderFont(face, requestedName: requested, context: context)
      let savedMode = context.allocationMode
      context.allocationMode = .global
      defer { context.allocationMode = savedMode }
      context.operands.push(
        try await ResourceRuntime.define(
          font,
          for: key,
          in: .literalName("Font"),
          origin: .automatic,
          context: context
        )
      )
    }
  }

  enum MakeFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["makefont"]

    func execute(context: isolated Context) async throws {
      let (matrixObject, fontObject) = try context.operands.pop2()
      context.operands.push(try makeDerivedFont(fontObject, matrix: readMatrix(matrixObject), context: context))
    }
  }

  enum ScaleFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["scalefont"]

    func execute(context: isolated Context) async throws {
      let (scaleObject, fontObject) = try context.operands.pop2()
      let scale = try numeric(scaleObject)
      guard scale.isFinite else { throw Error.rangeCheck }
      let matrix = GraphicsMatrix(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: 0)
      context.operands.push(try makeDerivedFont(fontObject, matrix: matrix, context: context))
    }
  }

  enum SelectFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["selectfont"]

    func execute(context: isolated Context) async throws {
      let (scaleOrMatrix, key) = try context.operands.pop2()
      context.operands.push(key)
      try await FindFont.instance.execute(context: context)
      let font = try context.operands.pop()
      let derived: Object
      if scaleOrMatrix.type == .array {
        derived = try makeDerivedFont(font, matrix: readMatrix(scaleOrMatrix), context: context)
      } else {
        let scale = try numeric(scaleOrMatrix)
        derived = try makeDerivedFont(
          font,
          matrix: GraphicsMatrix(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: 0),
          context: context
        )
      }
      try setCurrentFont(derived, context: context)
    }
  }

  enum SetFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setfont"]

    func execute(context: isolated Context) async throws {
      try setCurrentFont(context.operands.pop(), context: context)
    }
  }

  enum CurrentFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentfont"]

    func execute(context: isolated Context) async throws {
      guard let font = context.graphicsState.fontSource else { throw Error.invalidFont }
      context.operands.push(font)
    }
  }

  enum RootFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rootfont"]

    func execute(context: isolated Context) async throws {
      if let root = context.textRootFontSource {
        context.operands.push(root)
      } else {
        try await CurrentFont.instance.execute(context: context)
      }
    }
  }

  enum FindEncoding: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["findencoding"]

    func execute(context: isolated Context) async throws {
      let key = try canonicalResourceKey(context.operands.pop())
      context.operands.push(try await ResourceRuntime.find(key, in: .literalName("Encoding"), context: context))
    }
  }

  enum ComposeFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["composefont"]

    func execute(context: isolated Context) async throws {
      let (descendantsObject, cmapObject, keyObject) = try context.operands.pop3()
      let key = try canonicalResourceKey(keyObject)
      let name = try key.value(as: NameValue.self).value
      let cmap: Object
      if cmapObject.value is DictionaryValue {
        cmap = cmapObject
      } else {
        cmap = try await ResourceRuntime.find(cmapObject, in: .literalName("CMap"), context: context)
      }
      try CMapResourceValidation.instance.validateDefinition(key: key, instance: cmap, context: context)
      let requested = try arrayObjects(descendantsObject)
      guard !requested.isEmpty else { throw Error.rangeCheck }
      var descendants: [Object] = []
      descendants.reserveCapacity(requested.count)
      for requestedFont in requested {
        if requestedFont.value is DictionaryValue {
          descendants.append(requestedFont)
          continue
        }
        do {
          descendants.append(try await ResourceRuntime.find(
            requestedFont, in: .literalName("CIDFont"), context: context
          ))
        } catch Error.undefinedResource {
          descendants.append(try await ResourceRuntime.find(
            requestedFont, in: .literalName("Font"), context: context
          ))
        }
      }
      let vm = context.allocationMode
      let encoding = try Object.array(
        descendants.indices.map { .integer(Int32($0)) },
        access: .readOnly,
        vm: vm,
        kind: .literal
      )
      let vector = try Object.array(descendants, access: .readOnly, vm: vm, kind: .literal)
      try context.adopt(encoding)
      try context.adopt(vector)
      let matrix = try makeMatrixObject(.identity, context: context)
      let bounds = try Object.array([0, 0, 0, 0], access: .readOnly, vm: vm, kind: .literal)
      try context.adopt(bounds)
      let cmapDictionary = try cmap.value(as: DictionaryValue.self)
      let writingMode = try cmapDictionary.objectValue(forKeyIfExists: "WMode", as: IntegerValue.self)?.value ?? 0
      let dictionary = try context.makeDictionary([
        (.literalName("FontType"), .integer(0)),
        (.literalName("FontName"), .literalName(name)),
        (.literalName("FontMatrix"), matrix),
        (.literalName("FontBBox"), bounds),
        (.literalName("FMapType"), .integer(9)),
        (.literalName("Encoding"), encoding),
        (.literalName("FDepVector"), vector),
        (.literalName("CMap"), cmap),
        (.literalName("WMode"), .integer(writingMode)),
      ], access: .unlimited, vm: vm)
      let initialized = try initializeFont(dictionary, resourceName: name, context: context)
      context.operands.push(try await ResourceRuntime.define(
        initialized,
        for: key,
        in: .literalName("Font"),
        origin: .explicit,
        context: context
      ))
    }
  }

  enum CacheStatus: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["cachestatus"]

    func execute(context: isolated Context) async throws {
      let status = context.environment.fontManager.glyphCache.status()
      context.operands.push(
        .integer(context.userParameters.integer("MaxFontItem")),
        .integer(Int32(FontGlyphCache.maximumEntries)),
        .integer(Int32(clamping: status.entries)),
        .integer(Int32(FontGlyphCache.maximumEntries)),
        .integer(Int32(clamping: status.entries)),
        .integer(Int32(clamping: status.maximumBytes)),
        .integer(Int32(clamping: status.bytes))
      )
    }
  }

  enum SetCacheLimit: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcachelimit"]

    func execute(context: isolated Context) async throws {
      let limit: IntegerValue = try context.operands.popAs()
      context.userParameters.setInteger(
        min(max(limit.value, 0), Int32(FontGlyphCache.maximumItemBytes)),
        for: "MaxFontItem"
      )
    }
  }

  enum SetCacheParams: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcacheparams"]

    func execute(context: isolated Context) async throws {
      let values = try context.operands.popToMark()
      let parameters = Array(values.prefix(3))
      let integers = try parameters.map { try $0.value(as: IntegerValue.self).value }
      if integers.count > 2, !context.isSystemAdministratorJob { throw Error.invalidAccess }
      if let upper = integers.first {
        context.userParameters.setInteger(
          min(max(upper, 0), Int32(FontGlyphCache.maximumItemBytes)),
          for: "MaxFontItem"
        )
      }
      if integers.count > 1 {
        context.userParameters.setInteger(max(integers[1], 0), for: "MinFontCompress")
      }
      if integers.count > 2 {
        try context.environment.setFontCacheMaximum(
          integers[2],
          administrator: true
        )
      }
    }
  }

  enum CurrentCacheParams: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentcacheparams"]

    func execute(context: isolated Context) async throws {
      let status = context.environment.fontManager.glyphCache.status()
      context.operands.push(
        .integer(context.userParameters.integer("MaxFontItem")),
        .integer(context.userParameters.integer("MinFontCompress")),
        .integer(Int32(clamping: status.maximumBytes)),
        .mark
      )
    }
  }

  private static func setCurrentFont(_ object: Object, context: isolated Context) throws {
    let definition = try fontDefinition(object, context: context)
    try context.applyGraphicsOperation(.state(.setFont(definition.description))) {
      $0.fontSource = object
      $0.font = definition.description
    }
  }

  private static func makeDerivedFont(
    _ fontObject: Object,
    matrix: GraphicsMatrix,
    context: isolated Context
  ) throws -> Object {
    let source = try fontDefinition(fontObject, context: context)
    var entries: [(Object, Object)] = []
    try source.dictionary.forEachUnchecked { key, value in
      if key != "FID", key != "FontMatrix" { entries.append((key, value)) }
    }
    let combined = source.matrix.concatenated(with: matrix)
    let matrixObject = try makeMatrixObject(combined, context: context)
    entries.append((.literalName("FontMatrix"), matrixObject))
    let dictionary = try context.makeDictionary(entries, access: .unlimited, vm: context.allocationMode)
    return try initializeFont(dictionary, resourceName: source.description.resourceName, context: context)
  }

  private static func resolveProviderFace(
    _ requested: String,
    context: isolated Context
  ) async throws -> FontProviderFace? {
    for provider in context.environment.fontProviders {
      if let face = try await context.withUserTimeSuspended({
        try await provider.resolve(FontResourceQuery(name: requested, permitsSubstitution: false))
      }) { return face }
    }
    guard let substitute = standard35Aliases[requested] else { return nil }
    for provider in context.environment.fontProviders {
      if let face = try await context.withUserTimeSuspended({
        try await provider.resolve(FontResourceQuery(name: substitute, permitsSubstitution: true))
      }) { return face }
    }
    return nil
  }

  private static let standard35Aliases: [String: String] = [
    "Times-Roman": "Times-Roman", "Times-Bold": "Times-Bold",
    "Times-Italic": "Times-Italic", "Times-BoldItalic": "Times-BoldItalic",
    "Helvetica": "Helvetica", "Helvetica-Bold": "Helvetica-Bold",
    "Helvetica-Oblique": "Helvetica-Oblique", "Helvetica-BoldOblique": "Helvetica-BoldOblique",
    "Courier": "Courier", "Courier-Bold": "Courier-Bold",
    "Courier-Oblique": "Courier-Oblique", "Courier-BoldOblique": "Courier-BoldOblique",
    "Symbol": "Symbol", "ZapfDingbats": "ZapfDingbats",
  ]
}
