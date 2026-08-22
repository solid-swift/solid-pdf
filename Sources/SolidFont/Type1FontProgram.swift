import Foundation

package struct Type1FontProgram: Sendable, Hashable {
  private let charStrings: [String: Data]
  private let glyphOrder: [String]
  private let subroutines: [Data]
  private let limits: FontParsingLimits

  package init(data: Data, limits: FontParsingLimits = .default) throws {
    guard !data.isEmpty, data.count <= limits.maximumDataBytes else {
      throw data.isEmpty ? FontError.invalidData : FontError.limitExceeded
    }
    let encrypted = try Self.encryptedBytes(data)
    var cipher = Type1CipherState(seed: Type1CipherState.eexecSeed)
    var plaintext = Data(capacity: encrypted.count)
    for byte in encrypted { plaintext.append(cipher.decrypt(byte)) }
    guard plaintext.count >= 4 else { throw FontError.invalidData }
    let parsed = try Self.parse(Data(plaintext.dropFirst(4)), limits: limits)
    charStrings = parsed.charStrings
    glyphOrder = parsed.glyphOrder
    subroutines = parsed.subroutines
    self.limits = limits
  }

  package func glyph(named name: String, selector: FontGlyphSelector) throws -> FontGlyph {
    let resolvedName = charStrings[name] == nil ? ".notdef" : name
    var active: Set<String> = []
    let decoded = try decode(name: resolvedName, active: &active)
    return FontGlyph(
      selector: selector,
      metrics: FontGlyphMetrics(
        horizontalAdvance: decoded.advance,
        bounds: decoded.outline.bounds
      ),
      program: .outline(decoded.outline),
      resolvedGlyphIndex: glyphOrder.firstIndex(of: resolvedName).map(UInt32.init)
    )
  }

  private func decode(name: String, active: inout Set<String>) throws -> DecodedFontCharString {
    guard active.insert(name).inserted, active.count <= limits.maximumSubroutineDepth else {
      throw FontError.limitExceeded
    }
    defer { active.remove(name) }
    guard let bytes = charStrings[name] else { throw FontError.invalidData }
    let decoded = try FontCharStringDecoder.decode(
      bytes,
      dialect: .type1,
      localSubroutines: subroutines,
      limits: limits
    )
    guard !decoded.components.isEmpty else { return decoded }
    var elements = decoded.outline.elements
    for component in decoded.components {
      let componentName = Self.standardName(for: component.characterCode)
      let child = try decode(name: componentName, active: &active)
      elements.append(contentsOf: child.outline.elements.map { $0.translated(by: component.offset) })
    }
    return DecodedFontCharString(
      outline: FontOutline(elements: elements),
      advance: decoded.advance,
      components: decoded.components
    )
  }

  private static func encryptedBytes(_ data: Data) throws -> Data {
    if data.first == 0x80 {
      var cursor = 0
      var encrypted = Data()
      while cursor < data.count {
        guard cursor <= data.count - 2, data[cursor] == 0x80 else { throw FontError.invalidData }
        let kind = data[cursor + 1]
        cursor += 2
        if kind == 3 { break }
        guard (kind == 1 || kind == 2), cursor <= data.count - 4 else { throw FontError.invalidData }
        let length = Int(data[cursor]) | Int(data[cursor + 1]) << 8
          | Int(data[cursor + 2]) << 16 | Int(data[cursor + 3]) << 24
        cursor += 4
        guard length >= 0, cursor <= data.count - length else { throw FontError.invalidData }
        if kind == 2 { encrypted.append(data[cursor..<cursor + length]) }
        cursor += length
      }
      guard !encrypted.isEmpty else { throw FontError.invalidData }
      return encrypted
    }
    guard let marker = data.range(of: Data("eexec".utf8)) else { throw FontError.invalidData }
    var cursor = marker.upperBound
    while cursor < data.count, Self.isWhitespace(data[cursor]) { cursor += 1 }
    guard cursor <= data.count - 4 else { throw FontError.invalidData }
    let hexadecimal = data[cursor..<cursor + 4].allSatisfy(Self.isHexadecimal)
    if !hexadecimal { return Data(data[cursor...]) }
    var result = Data()
    var high: UInt8?
    while cursor < data.count {
      let byte = data[cursor]
      cursor += 1
      if isWhitespace(byte) { continue }
      guard let nibble = hexadecimalValue(byte) else { break }
      if let highNibble = high {
        result.append(highNibble << 4 | nibble)
        high = nil
      } else {
        high = nibble
      }
    }
    guard high == nil, !result.isEmpty else { throw FontError.invalidData }
    return result
  }

  private static func parse(
    _ data: Data,
    limits: FontParsingLimits
  ) throws -> (charStrings: [String: Data], glyphOrder: [String], subroutines: [Data]) {
    var scanner = Type1ProgramScanner(data: data)
    var lenIV = 4
    var foundSubroutines = false
    while let token = try scanner.next() {
      if token == "/lenIV", let value = try scanner.nextInteger() { lenIV = value }
      if token == "/Subrs" {
        foundSubroutines = true
        break
      }
    }
    guard foundSubroutines, lenIV >= -1, let declaredSubroutines = try scanner.nextInteger(),
      declaredSubroutines >= 0, declaredSubroutines <= limits.maximumObjects
    else { throw FontError.invalidData }
    var subroutines = Array(repeating: Data(), count: declaredSubroutines)
    var foundCharStrings = false
    while let token = try scanner.next() {
      if token == "/CharStrings" {
        foundCharStrings = true
        break
      }
      guard token == "dup" else { continue }
      guard let index = try scanner.nextInteger(), let length = try scanner.nextInteger(),
        let introducer = try scanner.next(), introducer == "RD" || introducer == "-|",
        subroutines.indices.contains(index)
      else { throw FontError.invalidData }
      subroutines[index] = try FontCharStringDecoder.decryptType1(
        scanner.binary(count: length),
        lenIV: lenIV
      )
    }
    guard foundCharStrings, let declaredGlyphs = try scanner.nextInteger(),
      declaredGlyphs > 0, declaredGlyphs <= limits.maximumGlyphs
    else { throw FontError.invalidData }
    while let token = try scanner.next(), token != "begin" {}
    var charStrings: [String: Data] = [:]
    var glyphOrder: [String] = []
    glyphOrder.reserveCapacity(declaredGlyphs)
    while charStrings.count < declaredGlyphs, let token = try scanner.next() {
      guard token.first == "/", token.count > 1 else { continue }
      let name = String(token.dropFirst())
      guard let length = try scanner.nextInteger(),
        let introducer = try scanner.next(), introducer == "RD" || introducer == "-|"
      else { throw FontError.invalidData }
      let program = try FontCharStringDecoder.decryptType1(scanner.binary(count: length), lenIV: lenIV)
      guard charStrings.updateValue(program, forKey: name) == nil else { throw FontError.invalidData }
      glyphOrder.append(name)
    }
    guard charStrings.count == declaredGlyphs, charStrings[".notdef"] != nil else {
      throw FontError.invalidData
    }
    return (charStrings, glyphOrder, subroutines)
  }

  private static func standardName(for code: UInt8) -> String {
    if code >= 65, code <= 90 { return String(UnicodeScalar(code)) }
    if code >= 97, code <= 122 { return String(UnicodeScalar(code)) }
    return standardNames[Int(code)] ?? ".notdef"
  }

  private static let standardNames: [Int: String] = [
    32: "space", 33: "exclam", 34: "quotedbl", 35: "numbersign", 36: "dollar",
    37: "percent", 38: "ampersand", 39: "quoteright", 40: "parenleft", 41: "parenright",
    42: "asterisk", 43: "plus", 44: "comma", 45: "hyphen", 46: "period", 47: "slash",
    48: "zero", 49: "one", 50: "two", 51: "three", 52: "four", 53: "five", 54: "six",
    55: "seven", 56: "eight", 57: "nine", 58: "colon", 59: "semicolon", 60: "less",
    61: "equal", 62: "greater", 63: "question", 64: "at", 91: "bracketleft", 92: "backslash",
    93: "bracketright", 94: "asciicircum", 95: "underscore", 96: "quoteleft",
    123: "braceleft", 124: "bar", 125: "braceright", 126: "asciitilde",
    161: "exclamdown", 162: "cent", 163: "sterling", 164: "fraction", 165: "yen",
    166: "florin", 167: "section", 168: "currency", 169: "quotesingle", 170: "quotedblleft",
    171: "guillemotleft", 172: "guilsinglleft", 173: "guilsinglright", 174: "fi", 175: "fl",
    177: "endash", 178: "dagger", 179: "daggerdbl", 180: "periodcentered", 182: "paragraph",
    183: "bullet", 184: "quotesinglbase", 185: "quotedblbase", 186: "quotedblright",
    187: "guillemotright", 188: "ellipsis", 189: "perthousand", 191: "questiondown",
    193: "grave", 194: "acute", 195: "circumflex", 196: "tilde", 197: "macron",
    198: "breve", 199: "dotaccent", 200: "dieresis", 202: "ring", 203: "cedilla",
    205: "hungarumlaut", 206: "ogonek", 207: "caron", 208: "emdash", 225: "AE",
    227: "ordfeminine", 232: "Lslash", 233: "Oslash", 234: "OE", 235: "ordmasculine",
    241: "ae", 245: "dotlessi", 248: "lslash", 249: "oslash", 250: "oe", 251: "germandbls",
  ]

  private static func isWhitespace(_ byte: UInt8) -> Bool { byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32 }
  private static func isHexadecimal(_ byte: UInt8) -> Bool { hexadecimalValue(byte) != nil }
  private static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: byte - 48
    case 65...70: byte - 55
    case 97...102: byte - 87
    default: nil
    }
  }
}

private struct Type1ProgramScanner {
  let data: Data
  var offset = 0

  mutating func next() throws -> String? {
    skipWhitespaceAndComments()
    guard offset < data.count else { return nil }
    let start = offset
    if data[offset] == 0x2F { offset += 1 }
    while offset < data.count, !isDelimiter(data[offset]) { offset += 1 }
    if start == offset { throw FontError.invalidData }
    guard let value = String(data: data[start..<offset], encoding: .isoLatin1) else {
      throw FontError.invalidData
    }
    return value
  }

  mutating func nextInteger() throws -> Int? {
    guard let token = try next() else { return nil }
    return Int(token)
  }

  mutating func binary(count: Int) throws -> Data {
    guard count >= 0 else { throw FontError.invalidData }
    guard offset < data.count, isWhitespace(data[offset]) else { throw FontError.invalidData }
    if data[offset] == 13, offset + 1 < data.count, data[offset + 1] == 10 { offset += 2 } else { offset += 1 }
    guard offset <= data.count - count else { throw FontError.invalidData }
    defer { offset += count }
    return data.subdata(in: offset..<offset + count)
  }

  private mutating func skipWhitespaceAndComments() {
    while offset < data.count {
      if isWhitespace(data[offset]) { offset += 1; continue }
      if data[offset] == 0x25 {
        while offset < data.count, data[offset] != 10, data[offset] != 13 { offset += 1 }
        continue
      }
      break
    }
  }

  private func isWhitespace(_ byte: UInt8) -> Bool { byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32 }
  private func isDelimiter(_ byte: UInt8) -> Bool {
    isWhitespace(byte) || [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(byte)
  }
}

private extension FontOutline.Element {
  func translated(by offset: FontPoint) -> Self {
    switch self {
    case .move(let point): .move(.init(x: point.x + offset.x, y: point.y + offset.y))
    case .line(let point): .line(.init(x: point.x + offset.x, y: point.y + offset.y))
    case .quadratic(let control, let end): .quadratic(
      control: .init(x: control.x + offset.x, y: control.y + offset.y),
      end: .init(x: end.x + offset.x, y: end.y + offset.y)
    )
    case .cubic(let control1, let control2, let end): .cubic(
      control1: .init(x: control1.x + offset.x, y: control1.y + offset.y),
      control2: .init(x: control2.x + offset.x, y: control2.y + offset.y),
      end: .init(x: end.x + offset.x, y: end.y + offset.y)
    )
    case .close: .close
    }
  }
}

private extension FontOutline {
  var bounds: FontBounds? {
    let points = elements.flatMap { element -> [FontPoint] in
      switch element {
      case .move(let point), .line(let point): [point]
      case .quadratic(let control, let end): [control, end]
      case .cubic(let first, let second, let end): [first, second, end]
      case .close: []
      }
    }
    guard let first = points.first else { return nil }
    return FontBounds(
      minimumX: points.dropFirst().reduce(first.x) { min($0, $1.x) },
      minimumY: points.dropFirst().reduce(first.y) { min($0, $1.y) },
      maximumX: points.dropFirst().reduce(first.x) { max($0, $1.x) },
      maximumY: points.dropFirst().reduce(first.y) { max($0, $1.y) }
    )
  }
}
