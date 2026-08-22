/// Metadata identifying the revision appended by an incremental update.
public struct PDFIncrementalUpdateRevision: Sendable, Hashable {
  /// The zero-based chronological revision ordinal in the resulting file.
  public let ordinal: Int
  /// The absolute offset of the appended cross-reference section.
  public let startCrossReferenceOffset: Int64
  /// The cross-reference representation used by the appended revision.
  public let representation: PDFCrossReferenceRepresentation

  /// Creates appended-revision metadata.
  public init(
    ordinal: Int,
    startCrossReferenceOffset: Int64,
    representation: PDFCrossReferenceRepresentation
  ) {
    self.ordinal = ordinal
    self.startCrossReferenceOffset = startCrossReferenceOffset
    self.representation = representation
  }
}
