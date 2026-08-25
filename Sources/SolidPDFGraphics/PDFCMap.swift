import Foundation

struct PDFCMap: Sendable, Hashable {
  struct CodeSpace: Sendable, Hashable {
    let lower: Data
    let upper: Data

    func contains(_ code: Data) -> Bool {
      code.count == lower.count && code.lexicographicallyPrecedes(lower) == false
        && upper.lexicographicallyPrecedes(code) == false
    }
  }

  struct DecodedCode: Sendable, Hashable {
    let bytes: Data
    let cid: UInt32?
    let notdefCID: UInt32?
  }

  var name: String?
  var writingMode = 0
  var isIdentity = false
  var codeSpaces: [CodeSpace] = []
  var cidMappings: [Data: UInt32] = [:]
  var notdefMappings: [Data: UInt32] = [:]
  var unicodeMappings: [Data: [Unicode.Scalar]] = [:]
  var useCMapNames: [String] = []

  func decode(_ bytes: Data, from offset: Int) throws -> DecodedCode {
    guard offset < bytes.count else { throw PDFCMapError.incompleteCode }
    let lengths = Set(codeSpaces.map { $0.lower.count }).sorted(by: >)
    for length in lengths where offset <= bytes.count - length {
      let code = Data(bytes[offset..<offset + length])
      guard codeSpaces.contains(where: { $0.contains(code) }) else { continue }
      let identityCID = isIdentity ? code.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } : nil
      return DecodedCode(bytes: code, cid: cidMappings[code] ?? identityCID, notdefCID: notdefMappings[code])
    }
    let couldBePartial = codeSpaces.contains { space in
      let available = bytes.count - offset
      guard available < space.lower.count else { return false }
      let prefix = Data(bytes[offset..<bytes.count])
      return Data(space.lower.prefix(available)).lexicographicallyPrecedes(prefix) == false
        || Data(space.upper.prefix(available)).lexicographicallyPrecedes(prefix) == false
    }
    throw couldBePartial ? PDFCMapError.incompleteCode : PDFCMapError.invalidCode
  }

  mutating func inherit(_ base: PDFCMap, maximumEntries: Int) throws {
    if codeSpaces.isEmpty { codeSpaces = base.codeSpaces }
    if cidMappings.isEmpty { isIdentity = base.isIdentity }
    for (key, value) in base.cidMappings where cidMappings[key] == nil { cidMappings[key] = value }
    for (key, value) in base.notdefMappings where notdefMappings[key] == nil { notdefMappings[key] = value }
    for (key, value) in base.unicodeMappings where unicodeMappings[key] == nil { unicodeMappings[key] = value }
    guard entryCount <= maximumEntries else { throw PDFCMapError.limitExceeded }
  }

  var entryCount: Int { cidMappings.count + notdefMappings.count + unicodeMappings.count }

  static func identity(vertical: Bool) -> Self {
    var map = Self(name: vertical ? "Identity-V" : "Identity-H", writingMode: vertical ? 1 : 0)
    map.isIdentity = true
    map.codeSpaces = [CodeSpace(lower: Data([0, 0]), upper: Data([0xFF, 0xFF]))]
    return map
  }
}

enum PDFCMapError: Error, Sendable, Hashable {
  case malformed
  case invalidCode
  case incompleteCode
  case limitExceeded
}

struct PDFCMapParser {
  fileprivate enum Token: Equatable {
    case integer(Int)
    case name(String)
    case bytes(Data)
    case array([Token])
    case keyword(String)
  }

  let maximumBytes: Int
  let maximumEntries: Int

  func parse(_ data: Data) throws -> PDFCMap {
    guard data.count <= maximumBytes else { throw PDFCMapError.limitExceeded }
    let tokens = try tokenize(data)
    var result = PDFCMap()
    var stack: [Token] = []
    var index = 0
    while index < tokens.count {
      let token = tokens[index]
      index += 1
      guard case .keyword(let keyword) = token else {
        stack.append(token)
        guard stack.count <= 1_024 else { throw PDFCMapError.limitExceeded }
        continue
      }
      switch keyword {
      case "begincodespacerange":
        try consumeCount(&stack, tokens: tokens, index: &index) { lower, upper in
          guard case .bytes(let lower) = lower, case .bytes(let upper) = upper,
            !lower.isEmpty, lower.count == upper.count, lower.count <= 8,
            upper.lexicographicallyPrecedes(lower) == false
          else { throw PDFCMapError.malformed }
          result.codeSpaces.append(.init(lower: lower, upper: upper))
        }
      case "begincidchar", "beginnotdefchar":
        let isNotdef = keyword == "beginnotdefchar"
        try consumeCount(&stack, tokens: tokens, index: &index) { source, target in
          guard case .bytes(let code) = source, case .integer(let cid) = target,
            cid >= 0, cid <= Int(UInt32.max)
          else { throw PDFCMapError.malformed }
          if isNotdef { result.notdefMappings[code] = UInt32(cid) }
          else { result.cidMappings[code] = UInt32(cid) }
        }
      case "begincidrange", "beginnotdefrange":
        let isNotdef = keyword == "beginnotdefrange"
        let count = try popCount(&stack)
        for _ in 0..<count {
          guard index <= tokens.count - 3,
            case .bytes(let lower) = tokens[index],
            case .bytes(let upper) = tokens[index + 1],
            case .integer(let firstCID) = tokens[index + 2]
          else { throw PDFCMapError.malformed }
          index += 3
          try expandRange(lower: lower, upper: upper, maximumEntries: maximumEntries - result.entryCount) {
            code, delta in
            let value = firstCID.addingReportingOverflow(delta)
            guard !value.overflow, value.partialValue >= 0, value.partialValue <= Int(UInt32.max) else {
              throw PDFCMapError.malformed
            }
            if isNotdef { result.notdefMappings[code] = UInt32(value.partialValue) }
            else { result.cidMappings[code] = UInt32(value.partialValue) }
          }
        }
      case "beginbfchar":
        try consumeCount(&stack, tokens: tokens, index: &index) { source, target in
          guard case .bytes(let code) = source, case .bytes(let value) = target else {
            throw PDFCMapError.malformed
          }
          result.unicodeMappings[code] = try unicodeScalars(value)
        }
      case "beginbfrange":
        let count = try popCount(&stack)
        for _ in 0..<count {
          guard index <= tokens.count - 3,
            case .bytes(let lower) = tokens[index], case .bytes(let upper) = tokens[index + 1]
          else { throw PDFCMapError.malformed }
          let target = tokens[index + 2]
          index += 3
          switch target {
          case .bytes(let first):
            try expandRange(lower: lower, upper: upper, maximumEntries: maximumEntries - result.entryCount) {
              code, delta in
              result.unicodeMappings[code] = try unicodeScalars(adding(delta, toBigEndian: first))
            }
          case .array(let values):
            var valueIndex = 0
            try expandRange(lower: lower, upper: upper, maximumEntries: maximumEntries - result.entryCount) {
              code, _ in
              guard valueIndex < values.count, case .bytes(let value) = values[valueIndex] else {
                throw PDFCMapError.malformed
              }
              valueIndex += 1
              result.unicodeMappings[code] = try unicodeScalars(value)
            }
          default: throw PDFCMapError.malformed
          }
        }
      case "usecmap":
        guard case .name(let name) = stack.popLast() else { throw PDFCMapError.malformed }
        result.useCMapNames.append(name)
      case "def":
        guard stack.count >= 2 else { stack.removeAll(keepingCapacity: true); continue }
        let value = stack.removeLast()
        let key = stack.removeLast()
        if key == .name("WMode"), case .integer(let mode) = value, mode == 0 || mode == 1 {
          result.writingMode = mode
        } else if key == .name("CMapName"), case .name(let name) = value {
          result.name = name
        }
        stack.removeAll(keepingCapacity: true)
      case "endcodespacerange", "endcidchar", "endnotdefchar", "endcidrange",
           "endnotdefrange", "endbfchar", "endbfrange", "begincmap", "endcmap":
        stack.removeAll(keepingCapacity: true)
      default:
        stack.removeAll(keepingCapacity: true)
      }
      guard result.entryCount <= maximumEntries else { throw PDFCMapError.limitExceeded }
    }
    guard !result.codeSpaces.isEmpty || !result.useCMapNames.isEmpty else { throw PDFCMapError.malformed }
    return result
  }

  private func consumeCount(
    _ stack: inout [Token],
    tokens: [Token],
    index: inout Int,
    consume: (Token, Token) throws -> Void
  ) throws {
    let count = try popCount(&stack)
    guard count <= maximumEntries, index <= tokens.count - count * 2 else { throw PDFCMapError.malformed }
    for _ in 0..<count {
      try consume(tokens[index], tokens[index + 1])
      index += 2
    }
  }

  private func popCount(_ stack: inout [Token]) throws -> Int {
    guard case .integer(let count) = stack.popLast(), count >= 0, count <= maximumEntries else {
      throw PDFCMapError.malformed
    }
    stack.removeAll(keepingCapacity: true)
    return count
  }

  private func expandRange(
    lower: Data,
    upper: Data,
    maximumEntries: Int,
    body: (Data, Int) throws -> Void
  ) throws {
    guard maximumEntries > 0, !lower.isEmpty, lower.count == upper.count, lower.count <= 8 else {
      throw PDFCMapError.limitExceeded
    }
    let lowerValue = integer(lower)
    let upperValue = integer(upper)
    guard lowerValue <= upperValue, upperValue - lowerValue < UInt64(maximumEntries) else {
      throw PDFCMapError.limitExceeded
    }
    for value in lowerValue...upperValue {
      try body(bigEndian(value, width: lower.count), Int(value - lowerValue))
    }
  }

  private func integer(_ bytes: Data) -> UInt64 { bytes.reduce(0) { ($0 << 8) | UInt64($1) } }

  private func bigEndian(_ value: UInt64, width: Int) -> Data {
    Data((0..<width).map { UInt8((value >> UInt64((width - $0 - 1) * 8)) & 0xFF) })
  }

  private func adding(_ delta: Int, toBigEndian bytes: Data) throws -> Data {
    guard !bytes.isEmpty, bytes.count <= 8 else { throw PDFCMapError.malformed }
    let value = integer(bytes).addingReportingOverflow(UInt64(delta))
    guard !value.overflow else { throw PDFCMapError.malformed }
    return bigEndian(value.partialValue, width: bytes.count)
  }

  private func unicodeScalars(_ bytes: Data) throws -> [Unicode.Scalar] {
    guard bytes.count.isMultiple(of: 2) else { throw PDFCMapError.malformed }
    let units = stride(from: 0, to: bytes.count, by: 2).map {
      UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])
    }
    var result: [Unicode.Scalar] = []
    var index = 0
    while index < units.count {
      let first = units[index]
      index += 1
      let value: UInt32
      if (0xD800...0xDBFF).contains(first) {
        guard index < units.count, (0xDC00...0xDFFF).contains(units[index]) else {
          throw PDFCMapError.malformed
        }
        value = 0x1_0000 + (UInt32(first - 0xD800) << 10) + UInt32(units[index] - 0xDC00)
        index += 1
      } else {
        guard !(0xDC00...0xDFFF).contains(first) else { throw PDFCMapError.malformed }
        value = UInt32(first)
      }
      guard let scalar = Unicode.Scalar(value) else { throw PDFCMapError.malformed }
      result.append(scalar)
    }
    return result
  }

  private func tokenize(_ data: Data) throws -> [Token] {
    var scanner = Scanner(data: data, maximumTokens: maximumEntries * 4 + 4_096)
    return try scanner.allTokens()
  }
}

private struct Scanner {
  let data: Data
  let maximumTokens: Int
  var index = 0
  var count = 0

  mutating func allTokens(untilArrayEnd: Bool = false) throws -> [PDFCMapParser.Token] {
    var result: [PDFCMapParser.Token] = []
    while true {
      skipWhitespaceAndComments()
      guard index < data.count else {
        guard !untilArrayEnd else { throw PDFCMapError.malformed }
        return result
      }
      if untilArrayEnd, data[index] == 0x5D { index += 1; return result }
      result.append(try token())
      count += 1
      guard count <= maximumTokens else { throw PDFCMapError.limitExceeded }
    }
  }

  mutating func token() throws -> PDFCMapParser.Token {
    let byte = data[index]
    if byte == 0x2F {
      index += 1
      return .name(readWord())
    }
    if byte == 0x3C, index + 1 < data.count, data[index + 1] != 0x3C {
      index += 1
      var nibbles: [UInt8] = []
      while index < data.count, data[index] != 0x3E {
        if let value = hex(data[index]) { nibbles.append(value) }
        else if !isWhitespace(data[index]) { throw PDFCMapError.malformed }
        index += 1
      }
      guard index < data.count else { throw PDFCMapError.malformed }
      index += 1
      if !nibbles.count.isMultiple(of: 2) { nibbles.append(0) }
      return .bytes(Data(stride(from: 0, to: nibbles.count, by: 2).map { nibbles[$0] << 4 | nibbles[$0 + 1] }))
    }
    if byte == 0x5B {
      index += 1
      return .array(try allTokens(untilArrayEnd: true))
    }
    if byte == 0x28 {
      index += 1
      var depth = 1
      var bytes = Data()
      while index < data.count, depth > 0 {
        let value = data[index]
        index += 1
        if value == 0x5C {
          guard index < data.count else { throw PDFCMapError.malformed }
          bytes.append(data[index])
          index += 1
        } else if value == 0x28 {
          depth += 1
          bytes.append(value)
        } else if value == 0x29 {
          depth -= 1
          if depth > 0 { bytes.append(value) }
        } else {
          bytes.append(value)
        }
      }
      guard depth == 0 else { throw PDFCMapError.malformed }
      return .bytes(bytes)
    }
    guard !isDelimiter(byte) else { throw PDFCMapError.malformed }
    let word = readWord()
    if let value = Int(word) { return .integer(value) }
    return .keyword(word)
  }

  mutating func readWord() -> String {
    let start = index
    while index < data.count, !isWhitespace(data[index]), !isDelimiter(data[index]) { index += 1 }
    return String(decoding: data[start..<index], as: UTF8.self)
  }

  mutating func skipWhitespaceAndComments() {
    while index < data.count {
      if isWhitespace(data[index]) { index += 1; continue }
      if data[index] == 0x25 {
        while index < data.count, data[index] != 0x0A, data[index] != 0x0D { index += 1 }
        continue
      }
      if index + 1 < data.count,
        (data[index] == 0x3C && data[index + 1] == 0x3C)
          || (data[index] == 0x3E && data[index + 1] == 0x3E)
      {
        index += 2
        continue
      }
      return
    }
  }

  func isWhitespace(_ byte: UInt8) -> Bool { [0, 9, 10, 12, 13, 32].contains(byte) }
  func isDelimiter(_ byte: UInt8) -> Bool { [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(byte) }
  func hex(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: byte - 0x30
    case 0x41...0x46: byte - 0x41 + 10
    case 0x61...0x66: byte - 0x61 + 10
    default: nil
    }
  }
}
