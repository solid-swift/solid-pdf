import Foundation

struct PDFParsedIndirectHeader: Sendable {
  let reference: PDFObjectReference
  let sourceOffset: Int64
}

struct PDFObjectParser<Session: PDFInputSourceSession> {
  var cursor: PDFParserCursor<Session>
  let limits: PDFParsingLimits
  var enclosingObject: PDFObjectReference?

  init(
    reader: PDFSourceReader<Session>,
    position: Int64 = 0,
    limits: PDFParsingLimits,
    enclosingObject: PDFObjectReference? = nil
  ) {
    cursor = PDFParserCursor(reader: reader, position: position)
    self.limits = limits
    self.enclosingObject = enclosingObject
  }

  var position: Int64 { cursor.position }

  mutating func parseHeader() async throws -> PDFFileVersion {
    let start = position
    guard try await cursor.consume(Array("%PDF-".utf8)) else {
      throw malformed(at: start, "The PDF header is missing.")
    }
    var bytes = [UInt8]()
    while let byte = try await cursor.peekByte(), byte != 0x0A, byte != 0x0D {
      guard bytes.count < 8 else { throw malformed(at: start, "The PDF version is invalid.") }
      bytes.append(try await cursor.readByte())
    }
    guard let raw = String(bytes: bytes, encoding: .ascii),
      let version = PDFFileVersion(rawValue: raw)
    else { throw malformed(at: start, "The PDF version is unsupported or malformed.") }
    return version
  }

  mutating func parseIndirectHeader() async throws -> PDFParsedIndirectHeader {
    try await skipWhitespaceAndComments()
    let start = position
    let objectNumber = try await parseUnsignedIntegerToken()
    try await requireWhitespace("The object number must be followed by whitespace.")
    let generationNumber = try await parseUnsignedIntegerToken()
    try await requireWhitespace("The generation number must be followed by whitespace.")
    try await requireKeyword("obj")
    guard objectNumber > 0, objectNumber <= Int64(Int.max), generationNumber <= 65_535 else {
      throw malformed(at: start, "The indirect object header is outside its valid range.")
    }
    let reference = PDFObjectReference(
      uncheckedObjectNumber: Int(objectNumber),
      generationNumber: Int(generationNumber)
    )
    enclosingObject = reference
    return PDFParsedIndirectHeader(reference: reference, sourceOffset: start)
  }

  mutating func parseObject(nesting: Int = 0) async throws -> PDFObject {
    guard nesting <= limits.maximumNesting else {
      throw limit(at: position, "The object nesting limit was exceeded.")
    }
    try await skipWhitespaceAndComments()
    let start = position
    guard let byte = try await cursor.peekByte() else {
      throw truncated(at: start, "A PDF object is missing.")
    }
    switch byte {
    case 0x2F:
      return .name(try await parseName())
    case 0x28:
      return .string(try await parseLiteralString())
    case 0x5B:
      return try await parseArray(nesting: nesting + 1)
    case 0x3C:
      _ = try await cursor.readByte()
      if try await cursor.consume(0x3C) {
        return try await parseDictionary(nesting: nesting + 1)
      }
      return .string(try await parseHexadecimalString(afterOpeningDelimiterAt: start))
    case 0x74:
      try await requireKeyword("true")
      return .boolean(true)
    case 0x66:
      try await requireKeyword("false")
      return .boolean(false)
    case 0x6E:
      try await requireKeyword("null")
      return .null
    case 0x2B, 0x2D, 0x2E, 0x30...0x39:
      return try await parseNumberOrReference()
    default:
      throw malformed(at: start, "The next token is not a valid PDF object.")
    }
  }

  mutating func skipWhitespaceAndComments() async throws {
    while let byte = try await cursor.peekByte() {
      if Self.isWhitespace(byte) {
        _ = try await cursor.readByte()
      } else if byte == 0x25 {
        _ = try await cursor.readByte()
        while let comment = try await cursor.peekByte(), comment != 0x0A, comment != 0x0D {
          _ = try await cursor.readByte()
        }
      } else {
        return
      }
    }
  }

  mutating func requireKeyword(_ keyword: String) async throws {
    let start = position
    guard try await cursor.consume(Array(keyword.utf8)) else {
      throw malformed(at: start, "Expected the keyword \(keyword).")
    }
    if let next = try await cursor.peekByte(), !Self.isWhitespace(next), !Self.isDelimiter(next) {
      throw malformed(at: start, "The keyword \(keyword) is not delimited.")
    }
  }

  mutating func consumeKeyword(_ keyword: String) async throws -> Bool {
    let original = cursor
    do {
      try await requireKeyword(keyword)
      return true
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      cursor = original
      return false
    }
  }

  mutating func parseUnsignedIntegerToken() async throws -> Int64 {
    let start = position
    var value: Int64 = 0
    var count = 0
    while let byte = try await cursor.peekByte(), (0x30...0x39).contains(byte) {
      _ = try await cursor.readByte()
      let digit = Int64(byte - 0x30)
      let (multiplied, multiplyOverflow) = value.multipliedReportingOverflow(by: 10)
      let (next, addOverflow) = multiplied.addingReportingOverflow(digit)
      guard !multiplyOverflow, !addOverflow else {
        throw limit(at: start, "The integer token exceeds supported precision.")
      }
      value = next
      count += 1
      guard count <= limits.maximumTokenBytes else {
        throw limit(at: start, "The numeric token exceeds the configured limit.")
      }
    }
    guard count > 0 else { throw malformed(at: start, "An unsigned integer is required.") }
    return value
  }

  private mutating func parseNumberOrReference() async throws -> PDFObject {
    let start = position
    let token = try await readRegularToken()
    let number = try parseNumber(token, at: start)
    guard case .integer(let objectNumber) = number, objectNumber > 0, objectNumber <= Int64(Int.max)
    else { return .number(number) }

    let afterNumber = cursor
    do {
      try await requireWhitespace("An indirect reference requires whitespace.")
      let generation = try await parseUnsignedIntegerToken()
      guard generation <= 65_535 else { throw malformed(at: start, "Invalid generation number.") }
      try await requireWhitespace("An indirect reference requires whitespace before R.")
      guard try await cursor.consume(0x52) else { throw malformed(at: position, "Expected R.") }
      if let next = try await cursor.peekByte(), !Self.isWhitespace(next), !Self.isDelimiter(next) {
        throw malformed(at: position, "The indirect reference is not delimited.")
      }
      return .reference(
        PDFObjectReference(
          uncheckedObjectNumber: Int(objectNumber),
          generationNumber: Int(generation)
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as PDFParsingError {
      switch error {
      case .sourceFailure, .documentClosed:
        throw error
      default:
        cursor = afterNumber
        return .number(number)
      }
    } catch {
      cursor = afterNumber
      return .number(number)
    }
  }

  private mutating func parseName() async throws -> PDFName {
    let start = position
    guard try await cursor.consume(0x2F) else { throw malformed(at: start, "Expected a name.") }
    var bytes = Data()
    while let byte = try await cursor.peekByte(), !Self.isWhitespace(byte), !Self.isDelimiter(byte) {
      _ = try await cursor.readByte()
      if byte == 0x23 {
        guard let first = try await cursor.peekByte(), let high = Self.hexadecimalValue(first) else {
          throw malformed(at: position, "A PDF name contains an invalid hexadecimal escape.")
        }
        _ = try await cursor.readByte()
        guard let second = try await cursor.peekByte(), let low = Self.hexadecimalValue(second) else {
          throw malformed(at: position, "A PDF name contains an invalid hexadecimal escape.")
        }
        _ = try await cursor.readByte()
        bytes.append((high << 4) | low)
      } else {
        bytes.append(byte)
      }
      guard bytes.count <= limits.maximumTokenBytes else {
        throw limit(at: start, "The PDF name exceeds the configured token limit.")
      }
    }
    return PDFName(bytes: bytes)
  }

  private mutating func parseLiteralString() async throws -> PDFString {
    let start = position
    guard try await cursor.consume(0x28) else { throw malformed(at: start, "Expected a string.") }
    var bytes = Data()
    var depth = 1
    while depth > 0 {
      let byte = try await cursor.readByte()
      switch byte {
      case 0x28:
        depth += 1
        bytes.append(byte)
      case 0x29:
        depth -= 1
        if depth > 0 { bytes.append(byte) }
      case 0x5C:
        try await parseStringEscape(into: &bytes)
      case 0x0D:
        _ = try await cursor.consume(0x0A)
        bytes.append(0x0A)
      case 0x0A:
        bytes.append(0x0A)
      default:
        bytes.append(byte)
      }
      guard bytes.count <= limits.maximumStringBytes else {
        throw limit(at: start, "The PDF string exceeds the configured limit.")
      }
      guard depth <= limits.maximumNesting else {
        throw limit(at: start, "The literal-string nesting limit was exceeded.")
      }
    }
    return PDFString(bytes: bytes, representation: .literal)
  }

  private mutating func parseStringEscape(into bytes: inout Data) async throws {
    let escaped = try await cursor.readByte()
    switch escaped {
    case 0x6E: bytes.append(0x0A)
    case 0x72: bytes.append(0x0D)
    case 0x74: bytes.append(0x09)
    case 0x62: bytes.append(0x08)
    case 0x66: bytes.append(0x0C)
    case 0x28, 0x29, 0x5C: bytes.append(escaped)
    case 0x0D:
      _ = try await cursor.consume(0x0A)
    case 0x0A:
      break
    case 0x30...0x37:
      var value = Int(escaped - 0x30)
      for _ in 0..<2 {
        guard let next = try await cursor.peekByte(), (0x30...0x37).contains(next) else { break }
        _ = try await cursor.readByte()
        value = value * 8 + Int(next - 0x30)
      }
      bytes.append(UInt8(truncatingIfNeeded: value))
    default:
      bytes.append(escaped)
    }
  }

  private mutating func parseHexadecimalString(
    afterOpeningDelimiterAt start: Int64
  ) async throws -> PDFString {
    var bytes = Data()
    var highNibble: UInt8?
    while let byte = try await cursor.peekByte() {
      _ = try await cursor.readByte()
      if byte == 0x3E {
        if let highNibble { bytes.append(highNibble << 4) }
        return PDFString(bytes: bytes, representation: .hexadecimal)
      }
      if Self.isWhitespace(byte) { continue }
      guard let nibble = Self.hexadecimalValue(byte) else {
        throw malformed(at: position - 1, "A hexadecimal string contains a non-hexadecimal byte.")
      }
      if let high = highNibble {
        bytes.append((high << 4) | nibble)
        try checkStringLimit(bytes.count, at: start)
        highNibble = nil
      } else {
        highNibble = nibble
      }
    }
    throw truncated(at: start, "The hexadecimal string is not terminated.")
  }

  private mutating func parseArray(nesting: Int) async throws -> PDFObject {
    let start = position
    guard try await cursor.consume(0x5B) else { throw malformed(at: start, "Expected an array.") }
    var values = [PDFObject]()
    while true {
      try await skipWhitespaceAndComments()
      if try await cursor.consume(0x5D) { return .array(values) }
      guard values.count < limits.maximumArrayElements else {
        throw limit(at: start, "The PDF array exceeds the configured element limit.")
      }
      values.append(try await parseObject(nesting: nesting))
    }
  }

  private mutating func parseDictionary(nesting: Int) async throws -> PDFObject {
    let start = position
    var values = [PDFName: PDFObject]()
    while true {
      try await skipWhitespaceAndComments()
      if try await cursor.consume([0x3E, 0x3E]) { return .dictionary(values) }
      guard values.count < limits.maximumDictionaryEntries else {
        throw limit(at: start, "The PDF dictionary exceeds the configured entry limit.")
      }
      guard try await cursor.peekByte() == 0x2F else {
        throw malformed(at: position, "A PDF dictionary key must be a name.")
      }
      let key = try await parseName()
      values[key] = try await parseObject(nesting: nesting)
    }
  }

  private mutating func readRegularToken() async throws -> Data {
    let start = position
    var bytes = Data()
    while let byte = try await cursor.peekByte(), !Self.isWhitespace(byte), !Self.isDelimiter(byte) {
      bytes.append(try await cursor.readByte())
      guard bytes.count <= limits.maximumTokenBytes else {
        throw limit(at: start, "The PDF token exceeds the configured limit.")
      }
    }
    guard !bytes.isEmpty else { throw malformed(at: start, "A token is required.") }
    return bytes
  }

  private func parseNumber(_ bytes: Data, at offset: Int64) throws -> PDFNumber {
    guard let string = String(data: bytes, encoding: .ascii),
      string.allSatisfy({ $0 == "+" || $0 == "-" || $0 == "." || $0.isNumber })
    else { throw malformed(at: offset, "The numeric token is invalid.") }
    if string.contains(".") {
      guard string != ".", string != "+.", string != "-.",
        let value = Double(string), value.isFinite
      else { throw malformed(at: offset, "The real number is invalid.") }
      return .real(value)
    }
    guard string != "+", string != "-", let value = Int64(string) else {
      throw limit(at: offset, "The integer exceeds supported precision.")
    }
    return .integer(value)
  }

  private mutating func requireWhitespace(_ message: String) async throws {
    guard let byte = try await cursor.peekByte(), Self.isWhitespace(byte) else {
      throw malformed(at: position, message)
    }
    try await skipWhitespaceAndComments()
  }

  private func checkStringLimit(_ count: Int, at offset: Int64) throws {
    guard count <= limits.maximumStringBytes else {
      throw limit(at: offset, "The PDF string exceeds the configured limit.")
    }
  }

  private func malformed(at offset: Int64, _ message: String) -> PDFParsingError {
    .malformed(.init(offset: offset, object: enclosingObject, message: message))
  }

  private func truncated(at offset: Int64, _ message: String) -> PDFParsingError {
    .truncated(.init(offset: offset, object: enclosingObject, message: message))
  }

  private func limit(at offset: Int64, _ message: String) -> PDFParsingError {
    .limitExceeded(.init(offset: offset, object: enclosingObject, message: message))
  }

  static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x00 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
  }

  static func isDelimiter(_ byte: UInt8) -> Bool {
    byte == 0x28 || byte == 0x29 || byte == 0x3C || byte == 0x3E || byte == 0x5B
      || byte == 0x5D || byte == 0x7B || byte == 0x7D || byte == 0x2F || byte == 0x25
  }

  static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: byte - 0x30
    case 0x41...0x46: byte - 0x41 + 10
    case 0x61...0x66: byte - 0x61 + 10
    default: nil
    }
  }
}
