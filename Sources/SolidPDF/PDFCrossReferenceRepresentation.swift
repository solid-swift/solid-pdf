/// The representation used by one PDF cross-reference revision.
public enum PDFCrossReferenceRepresentation: Sendable, Hashable {
  /// A classic `xref` table and trailer dictionary.
  case classic
  /// A PDF 1.5 cross-reference stream.
  case stream
  /// A classic table supplemented by an `/XRefStm` stream.
  case hybrid
}
