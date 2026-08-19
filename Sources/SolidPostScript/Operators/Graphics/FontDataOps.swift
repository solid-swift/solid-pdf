import Foundation
import SolidFont

extension Operators {
  static let fontDataOps: [OperatorValue] = [FontSetStartData.instance, CIDStartData.instance]

  enum FontSetStartData: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".fontsetstartdata"]

    func execute(context: isolated Context) async throws {
      if try context.operands.peek().type == .name {
        _ = try context.operands.pop().value(as: NameValue.self)
      }
      let count = try dataCount(context.operands.pop())
      let key = try canonicalResourceKey(context.operands.pop())
      let data = try await readCurrentFile(count: count, context: context)
      let collection: CompactFontCollection
      do {
        collection = try CompactFontCollection(data: data)
      } catch FontError.limitExceeded {
        throw Error.limitCheck
      } catch {
        throw Error.invalidFont
      }
      try await define(collection: collection, data: data, key: key, context: context)
    }
  }

  enum CIDStartData: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".cidstartdata"]

    func execute(context: isolated Context) async throws {
      let count = try dataCount(context.operands.pop())
      let format = try context.operands.pop().value(as: StringValue.self)
      try format.access.check(.read)
      let formatName = format.string
      let source = try await readCurrentFile(count: count, context: context)
      let data: Data
      switch formatName.lowercased() {
      case "binary":
        data = source
      case "hex":
        data = try decodeHex(source)
      default:
        throw Error.rangeCheck
      }
      let dictionary = try context.dictionaries.currentDictionary()
      let name = try dictionary.objectValue(forKey: "CIDFontName", as: NameValue.self).value
      let previousGlyphData = try dictionary.object(forKeyIfExists: "GlyphData")
      let glyphData = Object.string(data, access: .readOnly, vm: dictionary.vm, kind: .literal)
      try context.preflightAllocation(bytes: data.count + 16, vm: dictionary.vm)
      try context.adopt(glyphData)
      try context.updateDictionary(dictionary, value: glyphData, forKey: "GlyphData")
      let object = Object.dictionary(sharing: dictionary, kind: .literal)
      let savedMode = context.allocationMode
      context.allocationMode = dictionary.vm
      defer { context.allocationMode = savedMode }
      do {
        _ = try await ResourceRuntime.define(
          object,
          for: .literalName(name),
          in: .literalName("CIDFont"),
          origin: .explicit,
          context: context
        )
      } catch {
        if let previousGlyphData {
          try? context.updateDictionary(dictionary, value: previousGlyphData, forKey: "GlyphData")
        } else {
          _ = try? dictionary.removeObject(forKey: "GlyphData")
        }
        throw error
      }
    }
  }

  private static func define(
    collection: CompactFontCollection,
    data: Data,
    key: Object,
    context: isolated Context
  ) async throws {
    let savedLocalResources = context.localResources
    context.resourceLoadTransactions.append([])
    do {
      var fontSetEntries: [(Object, Object)] = []
      fontSetEntries.reserveCapacity(collection.faces.count)
      for face in collection.faces {
        let font = try compactFont(
          face,
          globalSubroutines: collection.globalSubroutines,
          strings: collection.strings,
          data: data,
          context: context
        )
        let name = Object.literalName(face.name)
        let initialized = try initializeFont(font, resourceName: face.name, context: context)
        _ = try await ResourceRuntime.define(
          initialized,
          for: name,
          in: .literalName("Font"),
          origin: .explicit,
          context: context
        )
        fontSetEntries.append((name, initialized))
      }
      let fontSet = try context.makeDictionary(
        fontSetEntries,
        access: .readOnly,
        vm: context.allocationMode
      )
      _ = try await ResourceRuntime.define(
        fontSet,
        for: key,
        in: .literalName("FontSet"),
        origin: .explicit,
        size: Int32(clamping: data.count),
        context: context
      )
      _ = context.resourceLoadTransactions.removeLast()
    } catch {
      let mutations = context.resourceLoadTransactions.removeLast()
      context.localResources = savedLocalResources
      try? context.environment.rollbackGlobalResourceMutations(mutations)
      throw error
    }
  }

  private static func compactFont(
    _ face: CompactFontFace,
    globalSubroutines: [Data],
    strings: [String],
    data: Data,
    context: isolated Context
  ) throws -> Object {
    let vm = context.allocationMode
    let glyphNames = face.charset.enumerated().map { index, identifier in
      compactGlyphName(identifier, glyphIndex: index + 1, strings: strings)
    }
    var charStringEntries: [(Object, Object)] = [
      (.literalName(".notdef"), try fontDataString(face.charStrings[0], vm: vm, context: context)),
    ]
    for index in glyphNames.indices {
      charStringEntries.append((
        .literalName(glyphNames[index]),
        try fontDataString(face.charStrings[index + 1], vm: vm, context: context)
      ))
    }
    let charStrings = try context.makeDictionary(charStringEntries, access: .readOnly, vm: vm)
    let localSubroutines = try fontDataArray(face.privateDictionary.localSubroutines, vm: vm, context: context)
    let globalSubroutines = try fontDataArray(globalSubroutines, vm: vm, context: context)
    let privateDictionary = try context.makeDictionary([
      (.literalName("Subrs"), localSubroutines),
      (.literalName("GlobalSubrs"), globalSubroutines),
      (.literalName("defaultWidthX"), .real(face.privateDictionary.defaultWidth)),
      (.literalName("nominalWidthX"), .real(face.privateDictionary.nominalWidth)),
    ], access: .readOnly, vm: vm)
    var encoding = Array(repeating: Object.literalName(".notdef"), count: 256)
    for (code, glyphIndex) in face.encoding where glyphIndex > 0 && Int(glyphIndex) <= glyphNames.count {
      encoding[Int(code)] = .literalName(glyphNames[Int(glyphIndex) - 1])
    }
    let encodingObject = try Object.array(encoding, access: .readOnly, vm: vm, kind: .literal)
    try context.adopt(encodingObject)
    let matrix = try makeMatrixObject(
      GraphicsMatrix(a: 0.001, b: 0, c: 0, d: 0.001, tx: 0, ty: 0),
      context: context
    )
    let bounds = try Object.array([0, 0, 0, 0], access: .readOnly, vm: vm, kind: .literal)
    try context.adopt(bounds)
    let asset = try fontDataString(data, vm: vm, context: context)
    return try context.makeDictionary([
      (.literalName("FontType"), .integer(2)),
      (.literalName("FontName"), .literalName(face.name)),
      (.literalName("FontMatrix"), matrix),
      (.literalName("FontBBox"), bounds),
      (.literalName("Encoding"), encodingObject),
      (.literalName("CharStrings"), charStrings),
      (.literalName("Private"), privateDictionary),
      (.literalName("CFFData"), asset),
    ], access: .unlimited, vm: vm)
  }

  private static func compactGlyphName(
    _ identifier: CompactFontGlyphIdentifier,
    glyphIndex: Int,
    strings: [String]
  ) -> String {
    switch identifier {
    case .cid(let cid):
      return "cid\(cid)"
    case .stringIdentifier(let identifier):
      let customIndex = Int(identifier) - 391
      return strings.indices.contains(customIndex) ? strings[customIndex] : "gid\(glyphIndex)"
    }
  }

  private static func fontDataArray(
    _ values: [Data],
    vm: VM,
    context: isolated Context
  ) throws -> Object {
    let strings = try values.map { try fontDataString($0, vm: vm, context: context) }
    let array = try Object.array(strings, access: .readOnly, vm: vm, kind: .literal)
    try context.adopt(array)
    return array
  }

  private static func fontDataString(_ data: Data, vm: VM, context: isolated Context) throws -> Object {
    try context.preflightAllocation(bytes: data.count + 16, vm: vm)
    let string = Object.string(data, access: .readOnly, vm: vm, kind: .literal)
    try context.adopt(string)
    return string
  }

  private static func dataCount(_ object: Object) throws -> Int {
    let value = try object.value(as: IntegerValue.self).value
    guard value >= 0 else { throw Error.rangeCheck }
    return Int(value)
  }

  private static func readCurrentFile(count: Int, context: isolated Context) async throws -> Data {
    guard let fileIndex = context.execution.firstIndex(where: { $0.source.type == .file }) else {
      throw Error.invalidFileAccess
    }
    let file = try context.execution[fileIndex].source.value(as: FileValue.self)
    var result = Data(capacity: count)
    while result.count < count {
      guard let chunk = try await context.read(max: count - result.count, from: file.file), !chunk.isEmpty else {
        throw Error.ioError
      }
      result.append(chunk)
    }
    return result
  }

  private static func decodeHex(_ source: Data) throws -> Data {
    var result = Data()
    var pendingHigh: UInt8?
    for byte in source {
      if byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32 { continue }
      let nibble: UInt8
      switch byte {
      case 48...57: nibble = byte - 48
      case 65...70: nibble = byte - 55
      case 97...102: nibble = byte - 87
      default: throw Error.ioError
      }
      if let high = pendingHigh {
        result.append(high << 4 | nibble)
        pendingHigh = nil
      } else {
        pendingHigh = nibble
      }
    }
    if let pendingHigh { result.append(pendingHigh << 4) }
    return result
  }
}
