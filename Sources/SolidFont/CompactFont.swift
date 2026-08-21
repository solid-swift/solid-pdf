import Foundation

/// A glyph name or CID assigned to one Compact Font Format glyph index.
public enum CompactFontGlyphIdentifier: Sendable, Hashable {
  /// A String INDEX identifier used by a name-keyed font.
  case stringIdentifier(UInt16)
  /// A character identifier used by a CID-keyed font.
  case cid(UInt16)
}

/// One font dictionary in a CID-keyed Compact Font Format face.
public struct CompactFontDictionary: Sendable, Hashable {
  /// Local Type 2 subroutines referenced by this dictionary.
  public let localSubroutines: [Data]
  /// The default glyph width.
  public let defaultWidth: Double
  /// The nominal glyph width.
  public let nominalWidth: Double

  /// Creates a compact font dictionary.
  public init(localSubroutines: [Data], defaultWidth: Double = 0, nominalWidth: Double = 0) {
    self.localSubroutines = localSubroutines
    self.defaultWidth = defaultWidth
    self.nominalWidth = nominalWidth
  }
}

/// An immutable CFF1 font face.
public struct CompactFontFace: Sendable, Hashable {
  /// The name stored in the CFF Name INDEX.
  public let name: String
  /// Type 2 charstrings ordered by glyph index.
  public let charStrings: [Data]
  /// Charset entries ordered by glyph index, excluding glyph zero.
  public let charset: [CompactFontGlyphIdentifier]
  /// Encoding entries mapping byte codes to glyph indexes.
  public let encoding: [UInt8: UInt32]
  /// The default private dictionary for a name-keyed font.
  public let privateDictionary: CompactFontDictionary
  /// Font dictionaries for a CID-keyed font.
  public let fontDictionaries: [CompactFontDictionary]
  /// A font-dictionary selector ordered by glyph index.
  public let fontDictionarySelection: [UInt16]
  /// Whether this face is CID-keyed.
  public let isCIDKeyed: Bool

  /// Creates an immutable compact font face.
  public init(
    name: String,
    charStrings: [Data],
    charset: [CompactFontGlyphIdentifier],
    encoding: [UInt8: UInt32],
    privateDictionary: CompactFontDictionary,
    fontDictionaries: [CompactFontDictionary] = [],
    fontDictionarySelection: [UInt16] = [],
    isCIDKeyed: Bool = false
  ) throws {
    guard !name.isEmpty, !charStrings.isEmpty, charset.count + 1 == charStrings.count else {
      throw FontError.invalidData
    }
    guard !isCIDKeyed || fontDictionarySelection.count == charStrings.count else {
      throw FontError.invalidData
    }
    self.name = name
    self.charStrings = charStrings
    self.charset = charset
    self.encoding = encoding
    self.privateDictionary = privateDictionary
    self.fontDictionaries = fontDictionaries
    self.fontDictionarySelection = fontDictionarySelection
    self.isCIDKeyed = isCIDKeyed
  }
}

/// An immutable Compact Font Format version 1 font collection.
public struct CompactFontCollection: Sendable, Hashable {
  /// Faces in Name INDEX order.
  public let faces: [CompactFontFace]
  /// Global Type 2 subroutines shared by every face.
  public let globalSubroutines: [Data]
  /// Custom strings from the CFF String INDEX.
  public let strings: [String]

  /// Parses a complete CFF1 font set.
  public init(data: Data, limits: FontParsingLimits = .default) throws {
    let parser = try CompactFontParser(data: data, limits: limits)
    let result = try parser.parse()
    self.faces = result.faces
    self.globalSubroutines = result.globalSubroutines
    self.strings = result.strings
  }
}

private struct CompactFontParser {
  struct Dictionary {
    var values: [UInt16: [Double]] = [:]

    subscript(operation: UInt16) -> [Double]? { values[operation] }
  }

  let data: Data
  let limits: FontParsingLimits

  init(data: Data, limits: FontParsingLimits) throws {
    guard !data.isEmpty, data.count <= limits.maximumDataBytes else {
      throw data.isEmpty ? FontError.invalidData : FontError.limitExceeded
    }
    self.data = data
    self.limits = limits
  }

  func parse() throws -> (faces: [CompactFontFace], globalSubroutines: [Data], strings: [String]) {
    guard data.count >= 4, data[0] == 1 else { throw FontError.unsupportedFormat }
    let headerSize = Int(data[2])
    let headerOffsetSize = Int(data[3])
    guard headerSize >= 4, headerSize <= data.count, (1...4).contains(headerOffsetSize) else {
      throw FontError.invalidData
    }
    var offset = headerSize
    let names = try index(at: &offset)
    let topDictionaries = try index(at: &offset)
    let stringData = try index(at: &offset)
    let globalSubroutines = try index(at: &offset)
    guard !names.isEmpty, names.count == topDictionaries.count, names.count <= limits.maximumObjects else {
      throw FontError.invalidData
    }
    let strings = try stringData.map(string)
    var faces: [CompactFontFace] = []
    faces.reserveCapacity(names.count)
    for faceIndex in names.indices {
      let name = try string(names[faceIndex])
      let topDictionary = try dictionary(topDictionaries[faceIndex])
      faces.append(try face(name: name, topDictionary: topDictionary))
    }
    return (faces, globalSubroutines, strings)
  }

  private func face(name: String, topDictionary: Dictionary) throws -> CompactFontFace {
    let charStringOffset = try requiredInteger(topDictionary[17], count: 1)
    var indexOffset = charStringOffset
    let charStrings = try index(at: &indexOffset)
    guard !charStrings.isEmpty, charStrings.count <= limits.maximumGlyphs else {
      throw charStrings.isEmpty ? FontError.invalidData : FontError.limitExceeded
    }
    let cidKeyed = topDictionary[0x0C1E] != nil
    let charset = try charset(
      at: optionalInteger(topDictionary[15], default: 0),
      glyphCount: charStrings.count,
      cidKeyed: cidKeyed
    )
    let encoding = cidKeyed
      ? [:]
      : try encoding(at: optionalInteger(topDictionary[16], default: 0), glyphCount: charStrings.count)
    let basePrivateDictionary = try privateDictionary(topDictionary[18])
    let fontDictionaries: [CompactFontDictionary]
    let selection: [UInt16]
    if cidKeyed {
      let dictionaryOffset = try requiredInteger(topDictionary[0x0C24], count: 1)
      var offset = dictionaryOffset
      fontDictionaries = try index(at: &offset).map { try privateDictionary(dictionary($0)[18]) }
      let selectionOffset = try requiredInteger(topDictionary[0x0C25], count: 1)
      selection = try fontDictionarySelection(
        at: selectionOffset,
        glyphCount: charStrings.count,
        dictionaryCount: fontDictionaries.count
      )
    } else {
      fontDictionaries = []
      selection = []
    }
    return try CompactFontFace(
      name: name,
      charStrings: charStrings,
      charset: charset,
      encoding: encoding,
      privateDictionary: basePrivateDictionary,
      fontDictionaries: fontDictionaries,
      fontDictionarySelection: selection,
      isCIDKeyed: cidKeyed
    )
  }

  private func index(at offset: inout Int) throws -> [Data] {
    let count = try unsigned(at: offset, bytes: 2)
    offset += 2
    guard count <= limits.maximumObjects else { throw FontError.limitExceeded }
    guard count > 0 else { return [] }
    guard offset < data.count else { throw FontError.invalidData }
    let offsetSize = Int(data[offset])
    offset += 1
    guard (1...4).contains(offsetSize) else { throw FontError.invalidData }
    let offsetTableBytes = try checkedMultiply(count + 1, offsetSize)
    guard offsetTableBytes <= limits.maximumIndexBytes, offset <= data.count - offsetTableBytes else {
      throw FontError.invalidData
    }
    var offsets: [Int] = []
    offsets.reserveCapacity(count + 1)
    for index in 0...count {
      offsets.append(try unsigned(at: offset + index * offsetSize, bytes: offsetSize))
    }
    offset += offsetTableBytes
    guard offsets.first == 1, let last = offsets.last, last >= 1 else { throw FontError.invalidData }
    let payloadBytes = last - 1
    guard payloadBytes <= limits.maximumIndexBytes, offset <= data.count - payloadBytes else {
      throw FontError.invalidData
    }
    var objects: [Data] = []
    objects.reserveCapacity(count)
    for index in 0..<count {
      let lower = offsets[index] - 1
      let upper = offsets[index + 1] - 1
      guard lower <= upper, upper <= payloadBytes else { throw FontError.invalidData }
      objects.append(data.subdata(in: offset + lower..<offset + upper))
    }
    offset += payloadBytes
    return objects
  }

  private func dictionary(_ bytes: Data) throws -> Dictionary {
    var dictionary = Dictionary()
    var operands: [Double] = []
    var offset = 0
    while offset < bytes.count {
      let first = bytes[offset]
      offset += 1
      if first <= 21 {
        let operation: UInt16
        if first == 12 {
          guard offset < bytes.count else { throw FontError.invalidData }
          operation = 0x0C00 | UInt16(bytes[offset])
          offset += 1
        } else {
          operation = UInt16(first)
        }
        dictionary.values[operation] = operands
        operands.removeAll(keepingCapacity: true)
      } else {
        operands.append(try dictionaryNumber(first, bytes: bytes, offset: &offset))
        guard operands.count <= limits.maximumOperandStack else { throw FontError.limitExceeded }
      }
    }
    guard operands.isEmpty else { throw FontError.invalidData }
    return dictionary
  }

  private func dictionaryNumber(_ first: UInt8, bytes: Data, offset: inout Int) throws -> Double {
    switch first {
    case 32...246:
      return Double(Int(first) - 139)
    case 247...250:
      guard offset < bytes.count else { throw FontError.invalidData }
      defer { offset += 1 }
      return Double((Int(first) - 247) * 256 + Int(bytes[offset]) + 108)
    case 251...254:
      guard offset < bytes.count else { throw FontError.invalidData }
      defer { offset += 1 }
      return Double(-(Int(first) - 251) * 256 - Int(bytes[offset]) - 108)
    case 28:
      guard offset <= bytes.count - 2 else { throw FontError.invalidData }
      defer { offset += 2 }
      return Double(Int16(bitPattern: UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])))
    case 29:
      guard offset <= bytes.count - 4 else { throw FontError.invalidData }
      defer { offset += 4 }
      let value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
        | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
      return Double(Int32(bitPattern: value))
    case 30:
      return try real(bytes: bytes, offset: &offset)
    default:
      throw FontError.invalidData
    }
  }

  private func real(bytes: Data, offset: inout Int) throws -> Double {
    var text = ""
    while offset < bytes.count {
      let byte = bytes[offset]
      offset += 1
      for nibble in [byte >> 4, byte & 15] {
        switch nibble {
        case 0...9: text.append(Character(String(nibble)))
        case 10: text.append(".")
        case 11: text.append("E")
        case 12: text.append(contentsOf: "E-")
        case 13: throw FontError.invalidData
        case 14: text.append("-")
        case 15:
          guard let value = Double(text), value.isFinite else { throw FontError.invalidData }
          return value
        default: throw FontError.invalidData
        }
      }
    }
    throw FontError.invalidData
  }

  private func privateDictionary(_ operands: [Double]?) throws -> CompactFontDictionary {
    guard let operands else { return CompactFontDictionary(localSubroutines: []) }
    guard operands.count == 2 else { throw FontError.invalidData }
    let size = try integer(operands[0])
    let offset = try integer(operands[1])
    guard size >= 0, offset >= 0, size <= limits.maximumIndexBytes, offset <= data.count - size else {
      throw FontError.invalidData
    }
    let dictionary = try dictionary(data.subdata(in: offset..<offset + size))
    let subroutines: [Data]
    if let relative = dictionary[19] {
      let subroutineOffset = try requiredInteger(relative, count: 1)
      var absolute = try checkedAdd(offset, subroutineOffset)
      subroutines = try index(at: &absolute)
    } else {
      subroutines = []
    }
    return CompactFontDictionary(
      localSubroutines: subroutines,
      defaultWidth: dictionary[20]?.first ?? 0,
      nominalWidth: dictionary[21]?.first ?? 0
    )
  }

  private func charset(at offset: Int, glyphCount: Int, cidKeyed: Bool) throws -> [CompactFontGlyphIdentifier] {
    guard glyphCount > 0 else { return [] }
    if offset <= 2 {
      guard !cidKeyed else { throw FontError.invalidData }
      return (1..<glyphCount).map { .stringIdentifier(UInt16(clamping: $0)) }
    }
    guard offset < data.count else { throw FontError.invalidData }
    var cursor = offset
    let format = data[cursor]
    cursor += 1
    var values: [UInt16] = []
    values.reserveCapacity(glyphCount - 1)
    switch format {
    case 0:
      for _ in 1..<glyphCount {
        values.append(UInt16(try unsigned(at: cursor, bytes: 2)))
        cursor += 2
      }
    case 1, 2:
      while values.count < glyphCount - 1 {
        let first = try unsigned(at: cursor, bytes: 2)
        cursor += 2
        let additionalBytes = format == 1 ? 1 : 2
        let additional = try unsigned(at: cursor, bytes: additionalBytes)
        cursor += additionalBytes
        guard first + additional <= Int(UInt16.max), values.count + additional + 1 <= glyphCount - 1 else {
          throw FontError.invalidData
        }
        for value in first...first + additional { values.append(UInt16(value)) }
      }
    default:
      throw FontError.invalidData
    }
    return values.map { cidKeyed ? .cid($0) : .stringIdentifier($0) }
  }

  private func encoding(at offset: Int, glyphCount: Int) throws -> [UInt8: UInt32] {
    if offset == 0 || offset == 1 { return [:] }
    guard offset < data.count else { throw FontError.invalidData }
    var cursor = offset
    let rawFormat = data[cursor]
    cursor += 1
    let format = rawFormat & 0x7F
    var result: [UInt8: UInt32] = [:]
    var glyph: UInt32 = 1
    switch format {
    case 0:
      guard cursor < data.count else { throw FontError.invalidData }
      let count = Int(data[cursor])
      cursor += 1
      guard count < glyphCount, cursor <= data.count - count else { throw FontError.invalidData }
      for code in data[cursor..<cursor + count] {
        result[code] = glyph
        glyph += 1
      }
      cursor += count
    case 1:
      guard cursor < data.count else { throw FontError.invalidData }
      let rangeCount = Int(data[cursor])
      cursor += 1
      for _ in 0..<rangeCount {
        guard cursor <= data.count - 2 else { throw FontError.invalidData }
        let first = Int(data[cursor])
        let additional = Int(data[cursor + 1])
        cursor += 2
        guard first + additional <= 255, Int(glyph) + additional < glyphCount else { throw FontError.invalidData }
        for code in first...first + additional {
          result[UInt8(code)] = glyph
          glyph += 1
        }
      }
    default:
      throw FontError.invalidData
    }
    if rawFormat & 0x80 != 0 {
      guard cursor < data.count else { throw FontError.invalidData }
      let supplementCount = Int(data[cursor])
      cursor += 1
      guard cursor <= data.count - supplementCount * 3 else { throw FontError.invalidData }
      cursor += supplementCount * 3
    }
    return result
  }

  private func fontDictionarySelection(at offset: Int, glyphCount: Int, dictionaryCount: Int) throws -> [UInt16] {
    guard offset < data.count, dictionaryCount > 0 else { throw FontError.invalidData }
    var cursor = offset
    let format = data[cursor]
    cursor += 1
    switch format {
    case 0:
      guard cursor <= data.count - glyphCount else { throw FontError.invalidData }
      return try data[cursor..<cursor + glyphCount].map {
        guard Int($0) < dictionaryCount else { throw FontError.invalidData }
        return UInt16($0)
      }
    case 3:
      let rangeCount = try unsigned(at: cursor, bytes: 2)
      cursor += 2
      guard rangeCount > 0 else { throw FontError.invalidData }
      var ranges: [(start: Int, dictionary: UInt16)] = []
      ranges.reserveCapacity(rangeCount)
      for _ in 0..<rangeCount {
        let start = try unsigned(at: cursor, bytes: 2)
        cursor += 2
        guard cursor < data.count, Int(data[cursor]) < dictionaryCount else { throw FontError.invalidData }
        ranges.append((start, UInt16(data[cursor])))
        cursor += 1
      }
      let sentinel = try unsigned(at: cursor, bytes: 2)
      guard ranges.first?.start == 0, sentinel == glyphCount else { throw FontError.invalidData }
      var result = Array(repeating: UInt16(0), count: glyphCount)
      for index in ranges.indices {
        let end = index + 1 < ranges.count ? ranges[index + 1].start : sentinel
        guard ranges[index].start < end, end <= glyphCount else { throw FontError.invalidData }
        for glyph in ranges[index].start..<end { result[glyph] = ranges[index].dictionary }
      }
      return result
    default:
      throw FontError.invalidData
    }
  }

  private func requiredInteger(_ operands: [Double]?, count: Int) throws -> Int {
    guard let operands, operands.count == count, let first = operands.first else { throw FontError.invalidData }
    return try integer(first)
  }

  private func optionalInteger(_ operands: [Double]?, default value: Int) throws -> Int {
    guard let operands else { return value }
    return try requiredInteger(operands, count: 1)
  }

  private func integer(_ value: Double) throws -> Int {
    guard value.isFinite, value.rounded(.towardZero) == value, value >= 0, value <= Double(Int.max) else {
      throw FontError.invalidData
    }
    return Int(value)
  }

  private func unsigned(at offset: Int, bytes count: Int) throws -> Int {
    guard count > 0, count <= 4, offset >= 0, offset <= data.count - count else { throw FontError.invalidData }
    return data[offset..<offset + count].reduce(0) { ($0 << 8) | Int($1) }
  }

  private func string(_ data: Data) throws -> String {
    guard let string = String(data: data, encoding: .ascii), !string.isEmpty else { throw FontError.invalidData }
    return string
  }

  private func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
    let (result, overflow) = left.addingReportingOverflow(right)
    guard !overflow else { throw FontError.limitExceeded }
    return result
  }

  private func checkedMultiply(_ left: Int, _ right: Int) throws -> Int {
    let (result, overflow) = left.multipliedReportingOverflow(by: right)
    guard !overflow else { throw FontError.limitExceeded }
    return result
  }
}
