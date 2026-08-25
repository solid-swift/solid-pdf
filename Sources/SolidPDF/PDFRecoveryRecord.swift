/// One explicit repair or inference applied while recovering a PDF.
public struct PDFRecoveryRecord: Sendable, Hashable {
  /// The document-scoped record identity.
  public let identifier: PDFRecoveryRecordIdentifier
  /// The affected structural area.
  public let kind: PDFRecoveryKind
  /// The authority supporting the repaired fact.
  public let classification: PDFRecoveryClassification
  /// Exact source evidence used by the recovery pass.
  public let sourceRanges: [PDFSourceRange]
  /// The affected indirect object, when applicable.
  public let object: PDFObjectReference?
  /// A stable explanation of the repair.
  public let message: String

  package init(
    identifier: PDFRecoveryRecordIdentifier,
    kind: PDFRecoveryKind,
    classification: PDFRecoveryClassification,
    sourceRanges: [PDFSourceRange],
    object: PDFObjectReference? = nil,
    message: String
  ) {
    self.identifier = identifier
    self.kind = kind
    self.classification = classification
    self.sourceRanges = sourceRanges
    self.object = object
    self.message = message
  }
}
