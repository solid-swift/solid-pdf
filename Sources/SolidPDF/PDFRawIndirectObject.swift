import Foundation

struct PDFRawIndirectObject: Sendable {
  let reference: PDFObjectReference
  let value: PDFObject
  let sourceRange: PDFSourceRange
  let streamRange: PDFSourceRange?
}

extension PDFObjectParser {
  mutating func parseRawIndirectObject(
    resolveStreamLength: (@Sendable (PDFObjectReference) async throws -> Int64)? = nil
  ) async throws -> PDFRawIndirectObject {
    let header = try await parseIndirectHeader()
    let value = try await parseObject()
    try await skipWhitespaceAndComments()
    var streamRange: PDFSourceRange?
    if case .dictionary(let dictionary) = value, try await consumeKeyword("stream") {
      try await consumeRequiredLineEnding(after: "stream")
      let streamStart = position
      let length: Int64
      if let direct = dictionary.pdfInteger(named: "Length") {
        length = direct
      } else if let reference = dictionary.pdfReference(named: "Length"),
        let resolveStreamLength
      {
        length = try await resolveStreamLength(reference)
      } else {
        throw PDFParsingError.malformed(
          .init(
            offset: streamStart,
            object: header.reference,
            message: "A directly parseable stream requires a direct nonnegative Length."
          )
        )
      }
      guard length >= 0, length <= Int64(Int.max) else {
        throw PDFParsingError.malformed(
          .init(
            offset: streamStart,
            object: header.reference,
            message: "The stream Length is outside its valid range."
          )
        )
      }
      streamRange = PDFSourceRange(uncheckedOffset: streamStart, length: Int(length))
      try await cursor.seek(to: streamStart + length)
      if try await cursor.consume(0x0D) {
        _ = try await cursor.consume(0x0A)
      } else {
        _ = try await cursor.consume(0x0A)
      }
      try await requireKeyword("endstream")
      try await skipWhitespaceAndComments()
    }
    try await requireKeyword("endobj")
    let rangeLength = position - header.sourceOffset
    guard rangeLength <= Int64(Int.max) else {
      throw PDFParsingError.limitExceeded(
        .init(
          offset: header.sourceOffset,
          object: header.reference,
          message: "The indirect object range exceeds supported limits."
        )
      )
    }
    return PDFRawIndirectObject(
      reference: header.reference,
      value: value,
      sourceRange: PDFSourceRange(uncheckedOffset: header.sourceOffset, length: Int(rangeLength)),
      streamRange: streamRange
    )
  }

  private mutating func consumeRequiredLineEnding(after keyword: String) async throws {
    if try await cursor.consume(0x0D) {
      _ = try await cursor.consume(0x0A)
      return
    }
    guard try await cursor.consume(0x0A) else {
      throw PDFParsingError.malformed(
        .init(
          offset: position,
          object: enclosingObject,
          message: "The \(keyword) keyword must be followed by a line ending."
        )
      )
    }
  }
}
