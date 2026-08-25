import Foundation

struct PDFParserSpan: ~Copyable {
  private let storage: Data
  private var lowerBound: Int
  private let upperBound: Int

  init(_ storage: Data) {
    self.storage = storage
    lowerBound = 0
    upperBound = storage.count
  }

  var count: Int { upperBound - lowerBound }
  var isEmpty: Bool { lowerBound == upperBound }
  var position: Int { lowerBound }

  mutating func readByte() throws -> UInt8 {
    guard lowerBound < upperBound else {
      throw PDFParsingError.truncated(
        .init(offset: Int64(lowerBound), message: "The bounded parser span is exhausted.")
      )
    }
    defer { lowerBound += 1 }
    return storage[lowerBound]
  }

  mutating func seek(to position: Int) throws {
    guard position >= 0, position <= upperBound else {
      throw PDFParsingError.malformed(
        .init(offset: Int64(lowerBound), message: "The parser span seek is outside its bounds.")
      )
    }
    lowerBound = position
  }

  mutating func readBigEndianInteger(byteCount: Int) throws -> UInt64 {
    guard (0...8).contains(byteCount), count >= byteCount else {
      throw PDFParsingError.truncated(
        .init(offset: Int64(lowerBound), message: "The big-endian integer is truncated.")
      )
    }
    var value: UInt64 = 0
    for _ in 0..<byteCount {
      value = (value << 8) | UInt64(try readByte())
    }
    return value
  }

  mutating func readLittleEndianInteger(byteCount: Int) throws -> UInt64 {
    guard (0...8).contains(byteCount), count >= byteCount else {
      throw PDFParsingError.truncated(
        .init(offset: Int64(lowerBound), message: "The little-endian integer is truncated.")
      )
    }
    var value: UInt64 = 0
    for shift in 0..<byteCount {
      value |= UInt64(try readByte()) << UInt64(shift * 8)
    }
    return value
  }

  mutating func atomically<Result>(
    _ operation: (inout PDFParserSpan) throws -> Result
  ) throws -> Result {
    let original = lowerBound
    do {
      return try operation(&self)
    } catch {
      lowerBound = original
      throw error
    }
  }
}
