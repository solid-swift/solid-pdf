import Foundation

struct PDFSignatureContentsToken: Sendable {
  let range: PDFSourceRange
  let bytes: Data
}

enum PDFSignatureSourceScanner {
  static func contentsToken(
    in source: Data,
    absoluteOffset: Int64
  ) throws -> PDFSignatureContentsToken {
    let bytes = [UInt8](source)
    var index = 0
    while index < bytes.count {
      switch bytes[index] {
      case 0x25:
        skipComment(bytes, index: &index)
      case 0x28:
        try skipLiteralString(bytes, index: &index)
      case 0x2F:
        let name = readName(bytes, index: &index)
        guard name == Array("Contents".utf8) else { continue }
        skipWhitespaceAndComments(bytes, index: &index)
        guard index < bytes.count, bytes[index] == 0x3C,
          index + 1 >= bytes.count || bytes[index + 1] != 0x3C
        else { continue }
        return try readHexString(bytes, index: &index, absoluteOffset: absoluteOffset)
      case 0x3C:
        if index + 1 < bytes.count, bytes[index + 1] == 0x3C {
          index += 2
        } else {
          try skipHexString(bytes, index: &index)
        }
      default:
        index += 1
      }
    }
    throw PDFParsingError.malformed(.init(
      offset: absoluteOffset,
      message: "The exact signature Contents token was not found."
    ))
  }

  private static func readHexString(
    _ source: [UInt8],
    index: inout Int,
    absoluteOffset: Int64
  ) throws -> PDFSignatureContentsToken {
    let start = index
    index += 1
    var highNibble: UInt8?
    var decoded = Data()
    while index < source.count {
      let byte = source[index]
      index += 1
      if byte == 0x3E {
        if let highNibble { decoded.append(highNibble << 4) }
        return PDFSignatureContentsToken(
          range: try PDFSourceRange(offset: absoluteOffset + Int64(start), length: index - start),
          bytes: decoded
        )
      }
      if isWhitespace(byte) { continue }
      guard let nibble = hexValue(byte) else {
        throw PDFParsingError.malformed(.init(
          offset: absoluteOffset + Int64(index - 1),
          message: "A signature Contents token contains a nonhexadecimal byte."
        ))
      }
      if let high = highNibble {
        decoded.append((high << 4) | nibble)
        highNibble = nil
      } else {
        highNibble = nibble
      }
    }
    throw PDFParsingError.truncated(.init(
      offset: absoluteOffset + Int64(start),
      message: "The signature Contents token is truncated."
    ))
  }

  private static func skipLiteralString(_ source: [UInt8], index: inout Int) throws {
    var depth = 0
    repeat {
      guard index < source.count else { throw PDFDERError.truncated(index) }
      let byte = source[index]
      index += 1
      if byte == 0x5C {
        if index < source.count { index += 1 }
      } else if byte == 0x28 {
        depth += 1
      } else if byte == 0x29 {
        depth -= 1
      }
    } while depth > 0
  }

  private static func skipHexString(_ source: [UInt8], index: inout Int) throws {
    index += 1
    while index < source.count, source[index] != 0x3E { index += 1 }
    guard index < source.count else { throw PDFDERError.truncated(index) }
    index += 1
  }

  private static func skipComment(_ source: [UInt8], index: inout Int) {
    while index < source.count, source[index] != 0x0A, source[index] != 0x0D { index += 1 }
  }

  private static func skipWhitespaceAndComments(_ source: [UInt8], index: inout Int) {
    while index < source.count {
      if isWhitespace(source[index]) {
        index += 1
      } else if source[index] == 0x25 {
        skipComment(source, index: &index)
      } else {
        return
      }
    }
  }

  private static func readName(_ source: [UInt8], index: inout Int) -> [UInt8] {
    index += 1
    let start = index
    while index < source.count, !isWhitespace(source[index]), !isDelimiter(source[index]) { index += 1 }
    return Array(source[start..<index])
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
  }

  private static func isDelimiter(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25: true
    default: false
    }
  }

  private static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: byte - 0x30
    case 0x41...0x46: byte - 0x41 + 10
    case 0x61...0x66: byte - 0x61 + 10
    default: nil
    }
  }
}
