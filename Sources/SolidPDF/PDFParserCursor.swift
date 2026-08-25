import Foundation

struct PDFParserCursor<Session: PDFInputSourceSession> {
  let reader: PDFSourceReader<Session>
  var position: Int64
  private var window: PDFSourceWindow?

  init(reader: PDFSourceReader<Session>, position: Int64 = 0) {
    self.reader = reader
    self.position = position
  }

  mutating func peekByte() async throws -> UInt8? {
    guard let window = try await containingWindow() else { return nil }
    return window.data[Int(position - window.offset)]
  }

  mutating func readByte() async throws -> UInt8 {
    guard let byte = try await peekByte() else {
      throw PDFParsingError.truncated(
        .init(offset: position, message: "The PDF input ended unexpectedly.")
      )
    }
    position += 1
    return byte
  }

  mutating func consume(_ byte: UInt8) async throws -> Bool {
    guard try await peekByte() == byte else { return false }
    position += 1
    return true
  }

  mutating func consume(_ bytes: [UInt8]) async throws -> Bool {
    let original = self
    for byte in bytes where try await readByte() != byte {
      self = original
      return false
    }
    return true
  }

  mutating func read(count: Int) async throws -> Data {
    guard count >= 0 else {
      throw PDFParsingError.malformed(
        .init(offset: position, message: "A negative byte count was requested.")
      )
    }
    let range = PDFSourceRange(uncheckedOffset: position, length: count)
    let data = try await reader.read(range)
    position += Int64(count)
    window = nil
    return data
  }

  mutating func seek(to position: Int64) async throws {
    let length = try await reader.length()
    guard position >= 0, position <= length else {
      throw PDFParsingError.sourceFailure(
        .init(offset: position, message: "The parser seek is outside the document.")
      )
    }
    self.position = position
    window = nil
  }

  mutating func atomically<Result>(
    _ operation: (inout PDFParserCursor<Session>) async throws -> Result
  ) async throws -> Result {
    var copy = self
    let result = try await operation(&copy)
    self = copy
    return result
  }

  private mutating func containingWindow() async throws -> PDFSourceWindow? {
    if let window, position >= window.offset, position < window.endOffset {
      return window
    }
    window = try await reader.window(containing: position)
    return window
  }
}
