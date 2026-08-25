/// An absolute byte range in a PDF input source.
public struct PDFSourceRange: Sendable, Hashable {
  /// The zero-based source offset.
  public let offset: Int64
  /// The number of bytes in the range.
  public let length: Int

  /// The first byte after this range.
  public var endOffset: Int64 { offset + Int64(length) }

  /// Creates a validated source range.
  public init(offset: Int64, length: Int) throws {
    guard offset >= 0, length >= 0, offset <= Int64.max - Int64(length) else {
      throw PDFSourceRangeError.invalidRange
    }
    self.offset = offset
    self.length = length
  }

  package init(uncheckedOffset offset: Int64, length: Int) {
    self.offset = offset
    self.length = length
  }
}

/// An error produced while constructing a PDF source range.
public enum PDFSourceRangeError: Error, Sendable, Hashable {
  /// The offset, length, or resulting end offset is invalid.
  case invalidRange
}
