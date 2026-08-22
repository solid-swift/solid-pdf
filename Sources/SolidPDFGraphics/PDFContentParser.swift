import Foundation
import SolidPDF

final class PDFContentParser {
  private let input: PDFContentInput
  private let revision: PDFRevisionIdentifier
  private let page: PDFPage
  private let maximumScratchBytes: Int
  private let resourceStack: [PDFObjectReference]

  init(
    input: PDFContentInput,
    revision: PDFRevisionIdentifier,
    page: PDFPage,
    maximumScratchBytes: Int,
    resourceStack: [PDFObjectReference] = []
  ) {
    self.input = input
    self.revision = revision
    self.page = page
    self.maximumScratchBytes = maximumScratchBytes
    self.resourceStack = resourceStack
  }

  func next() async throws -> PDFContentToken? {
    guard let first = try await firstSignificantByte() else { return nil }
    var last = first
    let value = try await parseValue(starting: first, depth: 0, last: &last, allowKeyword: true)
    let location = makeLocation(first: first, last: last)
    switch value {
    case .object(let object): return PDFContentToken(object: object, location: location)
    case .keyword(let keyword): return PDFContentToken(keyword: keyword, location: location)
    }
  }

  func close() async { await input.close() }

  func parseInlineImage(
    startingAt start: PDFContentLocation,
    rawByteCount: ([PDFName: PDFObject]) async throws -> Int
  ) async throws -> PDFInlineImage {
    var dictionary: [PDFName: PDFObject] = [:]
    while let key = try await next() {
      if case .keyword("ID") = key.value { break }
      guard case .object(.name(let name)) = key.value, let value = try await next(),
        case .object(let object) = value.value
      else { throw malformed("Malformed inline-image dictionary.", at: inlineByte(start)) }
      dictionary[name] = object
      try checkScratch(dictionary.count * 64, at: inlineByte(start))
    }
    guard let separator = try await input.read(), Self.isWhitespace(separator.value) else {
      throw malformed("Inline-image ID lacks required whitespace.", at: inlineByte(start))
    }
    if separator.value == 0x0D, let lineFeed = try await input.peek(), lineFeed.value == 0x0A {
      _ = try await input.read()
    }
    var last = inlineByte(start)
    var data = Data()
    if Self.hasInlineFilters(dictionary) {
      let decoder = try PDFInlineStreamDecoder(
        dictionary: dictionary,
        maximumFilters: 16,
        maximumDecodedBytes: maximumScratchBytes,
        diagnostic: .init(
          offset: start.decodedOffset,
          object: start.pageReference,
          message: "The inline-image filter configuration is invalid."
        )
      )
      var finished = false
      while !finished {
        guard let byte = try await input.read() else {
          throw malformed("Truncated filtered inline-image data.", at: last)
        }
        last = byte
        let result = try decoder.process(Data([byte.value]))
        let total = data.count.addingReportingOverflow(result.output.count)
        guard !total.overflow, total.partialValue <= maximumScratchBytes else {
          throw PDFGraphicsError.limitExceeded("Inline image exceeds interpretation scratch.", location: start)
        }
        data.append(result.output)
        finished = result.finished
      }
    } else {
      let length = try await rawByteCount(dictionary)
      guard length <= maximumScratchBytes else {
        throw PDFGraphicsError.limitExceeded("Inline image exceeds interpretation scratch.", location: start)
      }
      data.reserveCapacity(length)
      for _ in 0..<length {
        guard let byte = try await input.read() else { throw malformed("Truncated inline-image data.", at: last) }
        data.append(byte.value)
        last = byte
      }
    }
    guard let whitespace = try await input.read(), Self.isWhitespace(whitespace.value) else {
      throw malformed("Inline-image data lacks required trailing whitespace.", at: last)
    }
    while let following = try await input.peek(), Self.isWhitespace(following.value) {
      _ = try await input.read()
    }
    guard let e = try await input.read(), e.value == 0x45,
      let i = try await input.read(), i.value == 0x49,
      try await inlineImageTerminatorEndsToken()
    else { throw malformed("Inline-image EI terminator is invalid.", at: last) }
    return PDFInlineImage(
      dictionary: dictionary,
      data: data,
      location: PDFContentLocation(
        revision: start.revision,
        pageIndex: start.pageIndex,
        pageReference: start.pageReference,
        decodedOffset: start.decodedOffset,
        segments: start.segments + input.sourceSegment(from: last, through: i),
        resourceStack: start.resourceStack
      )
    )
  }

  private enum ParsedValue {
    case object(PDFObject)
    case keyword(String)
  }

  private func parseValue(
    starting first: PDFContentInput.Byte,
    depth: Int,
    last: inout PDFContentInput.Byte,
    allowKeyword: Bool
  ) async throws -> ParsedValue {
    guard depth <= 64 else { throw malformed("Content object nesting exceeds 64.", at: first) }
    switch first.value {
    case 0x2F:
      return .object(.name(PDFName(bytes: try await parseName(last: &last))))
    case 0x28:
      return .object(.string(PDFString(
        bytes: try await parseLiteralString(depth: depth, last: &last),
        representation: .literal
      )))
    case 0x3C:
      if let next = try await input.peek(), next.value == 0x3C {
        _ = try await input.read()
        last = next
        return .object(.dictionary(try await parseDictionary(depth: depth + 1, last: &last)))
      }
      return .object(.string(PDFString(
        bytes: try await parseHexadecimalString(last: &last),
        representation: .hexadecimal
      )))
    case 0x5B:
      return .object(.array(try await parseArray(depth: depth + 1, last: &last)))
    case 0x5D, 0x3E:
      throw malformed("Unexpected content delimiter.", at: first)
    default:
      let word = try await parseWord(starting: first, last: &last)
      if word == "true" { return .object(.boolean(true)) }
      if word == "false" { return .object(.boolean(false)) }
      if word == "null" { return .object(.null) }
      if let number = parseNumber(word) { return .object(.number(number)) }
      guard allowKeyword else { throw malformed("An operator keyword appeared inside a direct object.", at: first) }
      return .keyword(word)
    }
  }

  private func parseArray(depth: Int, last: inout PDFContentInput.Byte) async throws -> [PDFObject] {
    var result: [PDFObject] = []
    while let first = try await firstSignificantByte() {
      last = first
      if first.value == 0x5D { return result }
      let value = try await parseValue(starting: first, depth: depth, last: &last, allowKeyword: false)
      guard case .object(let object) = value else { throw malformed("Invalid array value.", at: first) }
      result.append(object)
      try checkScratch(result.count * MemoryLayout<PDFObject>.stride, at: first)
    }
    throw malformed("Unterminated content array.", at: last)
  }

  private func parseDictionary(
    depth: Int,
    last: inout PDFContentInput.Byte
  ) async throws -> [PDFName: PDFObject] {
    var result: [PDFName: PDFObject] = [:]
    while let first = try await firstSignificantByte() {
      last = first
      if first.value == 0x3E {
        guard let second = try await input.read(), second.value == 0x3E else {
          throw malformed("Malformed dictionary terminator.", at: first)
        }
        last = second
        return result
      }
      guard first.value == 0x2F else { throw malformed("Dictionary key is not a name.", at: first) }
      let key = PDFName(bytes: try await parseName(last: &last))
      guard let valueStart = try await firstSignificantByte() else {
        throw malformed("Dictionary value is missing.", at: last)
      }
      let parsed = try await parseValue(
        starting: valueStart,
        depth: depth,
        last: &last,
        allowKeyword: false
      )
      guard case .object(let value) = parsed else { throw malformed("Invalid dictionary value.", at: valueStart) }
      result[key] = value
      try checkScratch(result.count * 64, at: first)
    }
    throw malformed("Unterminated content dictionary.", at: last)
  }

  private func parseName(last: inout PDFContentInput.Byte) async throws -> Data {
    var result = Data()
    while let byte = try await input.peek(), !Self.isDelimiterOrWhitespace(byte.value) {
      _ = try await input.read()
      last = byte
      if byte.value == 0x23 {
        guard let high = try await input.read(), let low = try await input.read(),
          let highValue = Self.hexadecimal(high.value), let lowValue = Self.hexadecimal(low.value)
        else { throw malformed("Malformed name escape.", at: byte) }
        last = low
        result.append(highValue << 4 | lowValue)
      } else {
        result.append(byte.value)
      }
      try checkScratch(result.count, at: byte)
    }
    return result
  }

  private func parseLiteralString(
    depth: Int,
    last: inout PDFContentInput.Byte
  ) async throws -> Data {
    var result = Data()
    var nesting = 1
    while let byte = try await input.read() {
      last = byte
      switch byte.value {
      case 0x28:
        nesting += 1
        guard nesting + depth <= 64 else { throw malformed("String nesting exceeds 64.", at: byte) }
        result.append(byte.value)
      case 0x29:
        nesting -= 1
        if nesting == 0 { return result }
        result.append(byte.value)
      case 0x5C:
        guard let escaped = try await input.read() else { throw malformed("Truncated string escape.", at: byte) }
        last = escaped
        switch escaped.value {
        case 0x6E: result.append(0x0A)
        case 0x72: result.append(0x0D)
        case 0x74: result.append(0x09)
        case 0x62: result.append(0x08)
        case 0x66: result.append(0x0C)
        case 0x28, 0x29, 0x5C: result.append(escaped.value)
        case 0x0D:
          if let lineFeed = try await input.peek(), lineFeed.value == 0x0A {
            _ = try await input.read()
            last = lineFeed
          }
        case 0x0A: break
        case 0x30...0x37:
          var value = Int(escaped.value - 0x30)
          for _ in 0..<2 {
            guard let digit = try await input.peek(), (0x30...0x37).contains(digit.value) else { break }
            _ = try await input.read()
            last = digit
            value = value * 8 + Int(digit.value - 0x30)
          }
          result.append(UInt8(value & 0xFF))
        default: result.append(escaped.value)
        }
      case 0x0D:
        result.append(0x0A)
        if let lineFeed = try await input.peek(), lineFeed.value == 0x0A {
          _ = try await input.read()
          last = lineFeed
        }
      default: result.append(byte.value)
      }
      try checkScratch(result.count, at: byte)
    }
    throw malformed("Unterminated literal string.", at: last)
  }

  private func parseHexadecimalString(last: inout PDFContentInput.Byte) async throws -> Data {
    var result = Data()
    var pending: UInt8?
    while let byte = try await input.read() {
      last = byte
      if byte.value == 0x3E {
        if let pending { result.append(pending << 4) }
        return result
      }
      if Self.isWhitespace(byte.value) { continue }
      guard let nibble = Self.hexadecimal(byte.value) else {
        throw malformed("Invalid hexadecimal string digit.", at: byte)
      }
      if let high = pending {
        result.append(high << 4 | nibble)
        pending = nil
      } else {
        pending = nibble
      }
      try checkScratch(result.count + (pending == nil ? 0 : 1), at: byte)
    }
    throw malformed("Unterminated hexadecimal string.", at: last)
  }

  private func parseWord(
    starting first: PDFContentInput.Byte,
    last: inout PDFContentInput.Byte
  ) async throws -> String {
    var bytes = [first.value]
    while let byte = try await input.peek(), !Self.isDelimiterOrWhitespace(byte.value) {
      _ = try await input.read()
      last = byte
      bytes.append(byte.value)
      try checkScratch(bytes.count, at: byte)
    }
    guard bytes.allSatisfy({ $0 < 0x80 }) else { throw malformed("Operator token is not ASCII.", at: first) }
    return String(decoding: bytes, as: UTF8.self)
  }

  private func firstSignificantByte() async throws -> PDFContentInput.Byte? {
    while let byte = try await input.read() {
      if Self.isWhitespace(byte.value) { continue }
      if byte.value == 0x25 {
        while let comment = try await input.read(), comment.value != 0x0A, comment.value != 0x0D {}
        continue
      }
      return byte
    }
    return nil
  }

  private func parseNumber(_ text: String) -> PDFNumber? {
    guard !text.isEmpty else { return nil }
    let bytes = Array(text.utf8)
    var index = 0
    if bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
    guard index < bytes.count else { return nil }
    var digits = 0
    var decimalPoints = 0
    for byte in bytes[index...] {
      if (0x30...0x39).contains(byte) { digits += 1 }
      else if byte == 0x2E { decimalPoints += 1 }
      else { return nil }
    }
    guard digits > 0, decimalPoints <= 1 else { return nil }
    if decimalPoints == 0, let integer = Int64(text) { return .integer(integer) }
    guard let real = Double(text), real.isFinite else { return nil }
    return .real(real)
  }

  private func makeLocation(
    first: PDFContentInput.Byte,
    last: PDFContentInput.Byte
  ) -> PDFContentLocation {
    PDFContentLocation(
      revision: revision,
      pageIndex: page.index,
      pageReference: page.reference,
      decodedOffset: first.decodedOffset,
      segments: input.sourceSegment(from: first, through: last),
      resourceStack: resourceStack
    )
  }

  private func malformed(_ message: String, at byte: PDFContentInput.Byte) -> PDFGraphicsError {
    .malformedContent(
      message: message,
      operatorName: nil,
      location: makeLocation(first: byte, last: byte)
    )
  }

  private func checkScratch(_ count: Int, at byte: PDFContentInput.Byte) throws {
    guard count <= maximumScratchBytes else {
      throw PDFGraphicsError.limitExceeded(
        "PDF content token exceeds interpretation scratch.",
        location: makeLocation(first: byte, last: byte)
      )
    }
  }

  private func inlineImageTerminatorEndsToken() async throws -> Bool {
    guard let delimiter = try await input.peek() else { return true }
    return Self.isDelimiterOrWhitespace(delimiter.value)
  }

  private func inlineByte(_ location: PDFContentLocation) -> PDFContentInput.Byte {
    PDFContentInput.Byte(value: 0, streamIndex: 0, decodedOffset: location.decodedOffset)
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
  }

  private static func isDelimiterOrWhitespace(_ byte: UInt8) -> Bool {
    isWhitespace(byte) || [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(byte)
  }

  private static func hexadecimal(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: byte - 0x30
    case 0x41...0x46: byte - 0x41 + 10
    case 0x61...0x66: byte - 0x61 + 10
    default: nil
    }
  }

  private static func hasInlineFilters(_ dictionary: [PDFName: PDFObject]) -> Bool {
    switch dictionary["Filter"] ?? dictionary["F"] {
    case nil, .null: false
    case .array(let filters): !filters.isEmpty
    default: true
    }
  }
}
