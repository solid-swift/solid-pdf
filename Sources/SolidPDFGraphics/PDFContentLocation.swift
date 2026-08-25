import SolidPDF

/// Exact PDF source location associated with a content operation.
public struct PDFContentLocation: Sendable, Hashable {
  /// The selected document revision.
  public let revision: PDFRevisionIdentifier
  /// The zero-based source page index.
  public let pageIndex: Int
  /// The source page's indirect reference.
  public let pageReference: PDFObjectReference
  /// The operation's offset in concatenated decoded page content.
  public let decodedOffset: Int64
  /// Ordered content-stream segments contributing to the operation.
  public let segments: [PDFContentSourceSegment]
  /// Indirect resources active from outermost to innermost scope.
  public let resourceStack: [PDFObjectReference]

  /// Creates a PDF content location.
  public init(
    revision: PDFRevisionIdentifier,
    pageIndex: Int,
    pageReference: PDFObjectReference,
    decodedOffset: Int64,
    segments: [PDFContentSourceSegment],
    resourceStack: [PDFObjectReference] = []
  ) {
    self.revision = revision
    self.pageIndex = pageIndex
    self.pageReference = pageReference
    self.decodedOffset = decodedOffset
    self.segments = segments
    self.resourceStack = resourceStack
  }
}
