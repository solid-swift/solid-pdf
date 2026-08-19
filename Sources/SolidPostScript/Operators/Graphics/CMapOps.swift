import Foundation

extension Operators {
  static let cMapOps: [OperatorValue] = [
    BeginCMap.instance, EndCMap.instance, BeginCodeSpaceRange.instance, EndCodeSpaceRange.instance,
    UseFont.instance, BeginBFChar.instance, EndBFChar.instance, BeginBFRange.instance, EndBFRange.instance,
    BeginCIDChar.instance, EndCIDChar.instance, BeginCIDRange.instance, EndCIDRange.instance,
    BeginNotDefChar.instance, EndNotDefChar.instance, BeginNotDefRange.instance, EndNotDefRange.instance,
    BeginUseMatrix.instance, EndUseMatrix.instance, UseCMap.instance, StartData.instance,
  ]

  enum BeginCMap: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".begincmap"]
    func execute(context: isolated Context) async throws {
      let dictionary = try context.dictionaries.currentDictionary()
      let maps = ["CodeMap", "CodeMapFonts", "NotDefMap", "NotDefMapFonts", "CodeSpaceRanges", "FontMatrices"]
      for name in maps {
        try context.updateDictionary(
          dictionary,
          value: try context.makeDictionary([], access: .unlimited, vm: dictionary.vm),
          forKey: .literalName(name)
        )
      }
      try context.updateDictionary(dictionary, value: .integer(0), forKey: ".CMapFontIndex")
    }
  }

  enum EndCMap: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endcmap"]
    func execute(context: isolated Context) async throws {}
  }

  enum BeginCodeSpaceRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".begincodespacerange"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndCodeSpaceRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endcodespacerange"]
    func execute(context: isolated Context) async throws {
      let values = Array(try context.operands.popToMark().reversed())
      guard values.count.isMultiple(of: 2) else { throw Error.rangeCheck }
      let ranges = try context.dictionaries.currentDictionary()
        .objectValue(forKey: "CodeSpaceRanges", as: DictionaryValue.self)
      for index in stride(from: 0, to: values.count, by: 2) {
        let lower = try codeString(values[index])
        let upper = try codeString(values[index + 1])
        guard lower.count == upper.count, lower.lexicographicallyPrecedes(upper) || lower == upper else {
          throw Error.rangeCheck
        }
        try context.updateDictionary(ranges, value: values[index + 1], forKey: cMapCodeKey(lower))
      }
    }
  }

  enum UseFont: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".usefont"]
    func execute(context: isolated Context) async throws {
      let value: IntegerValue = try context.operands.popAs()
      guard value.value >= 0 else { throw Error.rangeCheck }
      try context.updateDictionary(
        context.dictionaries.currentDictionary(),
        value: .integer(value.value),
        forKey: ".CMapFontIndex"
      )
    }
  }

  enum BeginBFChar: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".beginbfchar"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndBFChar: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endbfchar"]
    func execute(context: isolated Context) async throws {
      try endCharacters(selector: .base, context: context)
    }
  }

  enum BeginCIDChar: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".begincidchar"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndCIDChar: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endcidchar"]
    func execute(context: isolated Context) async throws {
      try endCharacters(selector: .cid, context: context)
    }
  }

  enum BeginNotDefChar: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".beginnotdefchar"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndNotDefChar: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endnotdefchar"]
    func execute(context: isolated Context) async throws {
      try endCharacters(selector: .notdef, context: context)
    }
  }

  enum BeginBFRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".beginbfrange"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndBFRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endbfrange"]
    func execute(context: isolated Context) async throws { try endRanges(selector: .base, context: context) }
  }

  enum BeginCIDRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".begincidrange"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndCIDRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endcidrange"]
    func execute(context: isolated Context) async throws { try endRanges(selector: .cid, context: context) }
  }

  enum BeginNotDefRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".beginnotdefrange"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndNotDefRange: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endnotdefrange"]
    func execute(context: isolated Context) async throws { try endRanges(selector: .notdef, context: context) }
  }

  enum BeginUseMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".beginusematrix"]
    func execute(context: isolated Context) async throws { try beginEntries(context: context) }
  }

  enum EndUseMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".endusematrix"]
    func execute(context: isolated Context) async throws {
      let values = Array(try context.operands.popToMark().reversed())
      guard values.count == 1 else { throw Error.rangeCheck }
      _ = try readMatrix(values[0])
      let dictionary = try context.dictionaries.currentDictionary()
      let font = try dictionary.objectValue(forKey: ".CMapFontIndex", as: IntegerValue.self)
      let matrices = try dictionary.objectValue(forKey: "FontMatrices", as: DictionaryValue.self)
      try context.updateDictionary(matrices, value: values[0], forKey: .integer(font.value))
    }
  }

  enum UseCMap: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".usecmap"]
    func execute(context: isolated Context) async throws {
      let sourceObject = try context.operands.pop()
      let source: Object
      if sourceObject.value is DictionaryValue {
        source = sourceObject
      } else {
        source = try await ResourceRuntime.find(sourceObject, in: .literalName("CMap"), context: context)
      }
      let sourceDictionary = try source.value(as: DictionaryValue.self)
      let destination = try context.dictionaries.currentDictionary()
      for name in ["CodeMap", "CodeMapFonts", "NotDefMap", "NotDefMapFonts", "CodeSpaceRanges", "FontMatrices"] {
        guard let sourceMap = try sourceDictionary.objectValue(forKeyIfExists: .literalName(name), as: DictionaryValue.self)
        else { continue }
        let destinationMap = try destination.objectValue(forKey: .literalName(name), as: DictionaryValue.self)
        try context.updateDictionary(destinationMap, from: sourceMap)
      }
    }
  }

  enum StartData: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".startdata"]
    func execute(context: isolated Context) async throws {
      let source = try context.operands.pop()
      guard source.type == .string || source.type == .file else { throw Error.typeCheck }
      _ = try context.operands.pop().value(as: IntegerValue.self)
    }
  }

  private enum CMapSelector { case base, cid, notdef }

  private static func beginEntries(context: isolated Context) throws {
    _ = try context.operands.pop().value(as: IntegerValue.self)
    context.operands.push(.mark)
  }

  private static func endCharacters(selector: CMapSelector, context: isolated Context) throws {
    let values = Array(try context.operands.popToMark().reversed())
    guard values.count.isMultiple(of: 2) else { throw Error.rangeCheck }
    for index in stride(from: 0, to: values.count, by: 2) {
      try addMapping(code: values[index], target: values[index + 1], selector: selector, context: context)
    }
  }

  private static func endRanges(selector: CMapSelector, context: isolated Context) throws {
    let values = Array(try context.operands.popToMark().reversed())
    guard values.count.isMultiple(of: 3) else { throw Error.rangeCheck }
    for index in stride(from: 0, to: values.count, by: 3) {
      let lower = try codeString(values[index])
      let upper = try codeString(values[index + 1])
      guard lower.count == upper.count else { throw Error.rangeCheck }
      let lowerValue = try codeInteger(lower)
      let upperValue = try codeInteger(upper)
      guard lowerValue <= upperValue, upperValue - lowerValue <= 1_000_000 else { throw Error.limitCheck }
      for offset in 0...(upperValue - lowerValue) {
        let code = Object.string(
          codeData(lowerValue + offset, length: lower.count),
          access: .readOnly,
          vm: context.allocationMode,
          kind: .literal
        )
        try context.adopt(code)
        let target: Object
        if let base = values[index + 2].value as? IntegerValue {
          target = .integer(base.value + Int32(offset))
        } else {
          target = values[index + 2]
        }
        try addMapping(code: code, target: target, selector: selector, context: context)
      }
    }
  }

  private static func addMapping(
    code: Object,
    target: Object,
    selector: CMapSelector,
    context: isolated Context
  ) throws {
    let codeData = try codeString(code)
    switch selector {
    case .base:
      guard target.type == .name || target.type == .string else { throw Error.typeCheck }
    case .cid, .notdef:
      let value = try target.value(as: IntegerValue.self).value
      guard value >= 0 else { throw Error.rangeCheck }
    }
    let dictionary = try context.dictionaries.currentDictionary()
    let mapName: String
    let fontMapName: String
    if case .notdef = selector {
      mapName = "NotDefMap"
      fontMapName = "NotDefMapFonts"
    } else {
      mapName = "CodeMap"
      fontMapName = "CodeMapFonts"
    }
    let map = try dictionary.objectValue(forKey: .literalName(mapName), as: DictionaryValue.self)
    let fontMap = try dictionary.objectValue(forKey: .literalName(fontMapName), as: DictionaryValue.self)
    let font = try dictionary.objectValue(forKey: ".CMapFontIndex", as: IntegerValue.self)
    let key = cMapCodeKey(codeData)
    try context.updateDictionary(map, value: target, forKey: key)
    try context.updateDictionary(fontMap, value: .integer(font.value), forKey: key)
  }

  private static func codeString(_ object: Object) throws -> Data {
    let string = try object.value(as: StringValue.self)
    try string.access.check(.read)
    let data = try string.characters(in: string.range)
    guard !data.isEmpty, data.count <= 4 else { throw Error.rangeCheck }
    return data
  }

  private static func codeInteger(_ data: Data) throws -> Int {
    data.reduce(0) { ($0 << 8) | Int($1) }
  }

  private static func codeData(_ value: Int, length: Int) -> Data {
    Data((0..<length).map { shift in UInt8((value >> ((length - shift - 1) * 8)) & 255) })
  }
}

func cMapCodeKey(_ data: Data) -> Object {
  .literalName("@CMap.\(data.count).\(data.map { String(format: "%02X", $0) }.joined())")
}

func cMapCodeData(_ key: Object) throws -> Data {
  let name = try key.value(as: NameValue.self).value
  let parts = name.split(separator: ".", omittingEmptySubsequences: false)
  guard parts.count == 3, parts[0] == "@CMap", let count = Int(parts[1]), parts[2].count == count * 2
  else { throw Error.typeCheck }
  var data = Data()
  data.reserveCapacity(count)
  var index = parts[2].startIndex
  for _ in 0..<count {
    let end = parts[2].index(index, offsetBy: 2)
    guard let byte = UInt8(parts[2][index..<end], radix: 16) else { throw Error.typeCheck }
    data.append(byte)
    index = end
  }
  return data
}
