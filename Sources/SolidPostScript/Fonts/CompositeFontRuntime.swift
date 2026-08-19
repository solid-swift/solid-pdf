import Foundation

extension Operators {
  struct MappedCharacter {
    let sourceCode: UInt8
    let selector: GraphicsGlyphSelector
    let font: FontDefinition
    let effectiveMatrix: GraphicsMatrix
  }

  static func mapCharacters(
    _ bytes: Data,
    root: FontDefinition,
    context: isolated Context
  ) throws -> [MappedCharacter] {
    try mapCharacters(bytes, font: root, inheritedMatrix: .identity, depth: 0, context: context)
  }

  private static func mapCharacters(
    _ bytes: Data,
    font: FontDefinition,
    inheritedMatrix: GraphicsMatrix,
    depth: Int,
    context: isolated Context
  ) throws -> [MappedCharacter] {
    guard depth <= 5 else { throw Error.invalidFont }
    let effectiveMatrix = font.matrix.concatenated(with: inheritedMatrix)
    guard font.type == 0 else {
      return try bytes.map { byte in
        MappedCharacter(
          sourceCode: byte,
          selector: try glyphSelector(byte, font: font),
          font: font,
          effectiveMatrix: effectiveMatrix
        )
      }
    }

    let mappings = try decodeCompositeBytes(bytes, font: font)
    let encoding = try font.dictionary.objectValue(forKey: "Encoding", as: ArrayValue.self)
    let descendants = try font.dictionary.objectValue(forKey: "FDepVector", as: ArrayValue.self)
    var result: [MappedCharacter] = []
    for mapping in mappings {
      guard mapping.font >= 0, UInt(mapping.font) < encoding.count else { throw Error.rangeCheck }
      let descendantIndex = try encoding.object(at: UInt(mapping.font), for: .read)
        .value(as: IntegerValue.self).value
      guard descendantIndex >= 0, UInt(descendantIndex) < descendants.count else { throw Error.rangeCheck }
      let descendantObject = try descendants.object(at: UInt(descendantIndex), for: .read)
      let descendant = try fontDefinition(descendantObject, context: context)
      if descendant.type == 0 {
        guard case .code(let code) = mapping.selector else { throw Error.invalidFont }
        result.append(contentsOf: try mapCharacters(
          code,
          font: descendant,
          inheritedMatrix: effectiveMatrix,
          depth: depth + 1,
          context: context
        ))
        continue
      }
      let selector: GraphicsGlyphSelector
      switch mapping.selector {
      case .name(let name): selector = .name(name)
      case .cid(let cid): selector = .cid(cid)
      case .code(let code):
        guard code.count == 1, let byte = code.first else { throw Error.rangeCheck }
        if try descendant.dictionary.object(forKeyIfExists: "CIDFontType") != nil { throw Error.invalidFont }
        selector = try glyphSelector(byte, font: descendant)
      }
      result.append(MappedCharacter(
        sourceCode: mapping.sourceCode,
        selector: selector,
        font: descendant,
        effectiveMatrix: descendant.matrix.concatenated(with: effectiveMatrix)
      ))
    }
    return result
  }

  private enum CompositeSelector {
    case code(Data)
    case name(String)
    case cid(UInt32)
  }

  private struct CompositeMapping {
    let sourceCode: UInt8
    let font: Int32
    let selector: CompositeSelector
  }

  private static func decodeCompositeBytes(_ bytes: Data, font: FontDefinition) throws -> [CompositeMapping] {
    let type = try font.dictionary.objectValue(forKey: "FMapType", as: IntegerValue.self).value
    switch type {
    case 2:
      guard bytes.count.isMultiple(of: 2) else { throw Error.rangeCheck }
      return stride(from: 0, to: bytes.count, by: 2).map {
        CompositeMapping(sourceCode: bytes[$0 + 1], font: Int32(bytes[$0]), selector: .code(Data([bytes[$0 + 1]])))
      }
    case 3, 7:
      return try decodeEscape(bytes, font: font, doubleEscape: type == 7)
    case 4:
      return bytes.map {
        CompositeMapping(sourceCode: $0, font: Int32($0 >> 7), selector: .code(Data([$0 & 0x7f])))
      }
    case 5:
      guard bytes.count.isMultiple(of: 2) else { throw Error.rangeCheck }
      return stride(from: 0, to: bytes.count, by: 2).map { index in
        let value = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
        return CompositeMapping(
          sourceCode: bytes[index + 1],
          font: Int32(value >> 7),
          selector: .code(Data([UInt8(value & 0x7f)]))
        )
      }
    case 6:
      return try decodeSubsVector(bytes, font: font)
    case 8:
      return try decodeShift(bytes, font: font)
    case 9:
      return try decodeCMap(bytes, font: font)
    default:
      throw Error.invalidFont
    }
  }

  private static func decodeEscape(
    _ bytes: Data,
    font: FontDefinition,
    doubleEscape: Bool
  ) throws -> [CompositeMapping] {
    let escape = try byteEntry("EscChar", default: 255, dictionary: font.dictionary)
    var selected: Int32 = 0
    var index = 0
    var result: [CompositeMapping] = []
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      if byte == escape {
        guard index < bytes.count else { throw Error.rangeCheck }
        selected = Int32(bytes[index])
        index += 1
        if doubleEscape, selected == Int32(escape) {
          guard index < bytes.count else { throw Error.rangeCheck }
          selected = Int32(bytes[index]) + 256
          index += 1
        }
      } else {
        result.append(CompositeMapping(sourceCode: byte, font: selected, selector: .code(Data([byte]))))
      }
    }
    return result
  }

  private static func decodeShift(_ bytes: Data, font: FontDefinition) throws -> [CompositeMapping] {
    let shiftOut = try byteEntry("ShiftOut", default: 14, dictionary: font.dictionary)
    let shiftIn = try byteEntry("ShiftIn", default: 15, dictionary: font.dictionary)
    var selected: Int32 = 0
    var result: [CompositeMapping] = []
    for byte in bytes {
      if byte == shiftOut { selected = 1 }
      else if byte == shiftIn { selected = 0 }
      else { result.append(CompositeMapping(sourceCode: byte, font: selected, selector: .code(Data([byte])))) }
    }
    return result
  }

  private static func decodeSubsVector(_ bytes: Data, font: FontDefinition) throws -> [CompositeMapping] {
    let vector = try font.dictionary.objectValue(forKey: "SubsVector", as: StringValue.self)
    let data = try vector.characters(in: vector.range)
    guard let first = data.first else { throw Error.invalidFont }
    let length = Int(first) + 1
    guard length <= MemoryLayout<Int32>.size, (data.count - 1).isMultiple(of: length), bytes.count.isMultiple(of: length)
    else { throw Error.invalidFont }
    var bounds: [Int] = []
    var base = 0
    for start in stride(from: 1, to: data.count, by: length) {
      base += try codeInteger(Data(data[start..<(start + length)]))
      bounds.append(base)
    }
    return try stride(from: 0, to: bytes.count, by: length).map { start in
      let value = try codeInteger(Data(bytes[start..<(start + length)]))
      let font = Int32(bounds.firstIndex(where: { value < $0 }) ?? bounds.count)
      let lower = font == 0 ? 0 : bounds[Int(font) - 1]
      return CompositeMapping(
        sourceCode: bytes[start + length - 1],
        font: font,
        selector: .code(codeData(value - lower, minimumLength: 1))
      )
    }
  }

  private static func decodeCMap(_ bytes: Data, font: FontDefinition) throws -> [CompositeMapping] {
    let cmap = try font.dictionary.objectValue(forKey: "CMap", as: DictionaryValue.self)
    let ranges = try cmap.objectValue(forKey: "CodeSpaceRanges", as: DictionaryValue.self)
    let map = try cmap.objectValue(forKey: "CodeMap", as: DictionaryValue.self)
    let fonts = try cmap.objectValue(forKey: "CodeMapFonts", as: DictionaryValue.self)
    let notdef = try cmap.objectValue(forKeyIfExists: "NotDefMap", as: DictionaryValue.self)
    let notdefFonts = try cmap.objectValue(forKeyIfExists: "NotDefMapFonts", as: DictionaryValue.self)
    var index = 0
    var result: [CompositeMapping] = []
    while index < bytes.count {
      var code: Data?
      for length in 1...4 where index + length <= bytes.count {
        let candidate = Data(bytes[index..<(index + length)])
        if try codeMatches(candidate, ranges: ranges) { code = candidate }
      }
      guard let code else { throw Error.rangeCheck }
      let key = cMapCodeKey(code)
      let target = try map.object(forKeyIfExists: key) ?? notdef?.object(forKeyIfExists: key) ?? .integer(0)
      let selected = try fonts.objectValue(forKeyIfExists: key, as: IntegerValue.self)?.value
        ?? notdefFonts?.objectValue(forKeyIfExists: key, as: IntegerValue.self)?.value ?? 0
      let selector: CompositeSelector
      if let name = target.value as? NameValue { selector = .name(name.value) }
      else if let cid = target.value as? IntegerValue {
        guard cid.value >= 0 else { throw Error.rangeCheck }
        selector = .cid(UInt32(cid.value))
      } else if let string = target.value as? StringValue {
        selector = .code(try string.characters(in: string.range))
      } else { throw Error.invalidFont }
      result.append(CompositeMapping(
        sourceCode: code.last ?? 0,
        font: selected,
        selector: selector
      ))
      index += code.count
    }
    return result
  }

  private static func codeMatches(_ code: Data, ranges: DictionaryValue) throws -> Bool {
    var matches = false
    try ranges.forEachUnchecked { lowerObject, upperObject in
      let lower = try cMapCodeData(lowerObject)
      let upper = try upperObject.value(as: StringValue.self).characters(in: upperObject.value(as: StringValue.self).range)
      if lower.count == code.count,
        !code.lexicographicallyPrecedes(lower),
        !upper.lexicographicallyPrecedes(code)
      {
        matches = true
      }
    }
    return matches
  }

  private static func byteEntry(_ name: String, default defaultValue: UInt8, dictionary: DictionaryValue) throws -> UInt8 {
    let value = try dictionary.objectValue(forKeyIfExists: .literalName(name), as: IntegerValue.self)?.value
      ?? Int32(defaultValue)
    guard (0...255).contains(value) else { throw Error.invalidFont }
    return UInt8(value)
  }

  private static func codeInteger(_ data: Data) throws -> Int {
    guard data.count <= MemoryLayout<Int32>.size else { throw Error.rangeCheck }
    return data.reduce(0) { ($0 << 8) | Int($1) }
  }

  private static func codeData(_ value: Int, minimumLength: Int) -> Data {
    let significant = max(minimumLength, value == 0 ? 1 : (Int.bitWidth - value.leadingZeroBitCount + 7) / 8)
    return Data((0..<significant).map { UInt8((value >> (($0.distance(to: significant - 1)) * 8)) & 255) })
  }
}
