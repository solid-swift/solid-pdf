import SolidPDF

/// The decoded interval contributed by one page-content stream.
public struct PDFContentSourceSegment: Sendable, Hashable {
  /// The containing stream's indirect reference, when available.
  public let streamReference: PDFObjectReference?
  /// The stream's exact encoded source range.
  public let encodedRange: PDFSourceRange
  /// The offset in the exact decoded concatenation of page streams.
  public let decodedOffset: Int64
  /// The number of contributing decoded bytes.
  public let decodedLength: Int

  /// Creates a content source segment.
  public init(
    streamReference: PDFObjectReference?,
    encodedRange: PDFSourceRange,
    decodedOffset: Int64,
    decodedLength: Int
  ) {
    self.streamReference = streamReference
    self.encodedRange = encodedRange
    self.decodedOffset = decodedOffset
    self.decodedLength = decodedLength
  }
}
