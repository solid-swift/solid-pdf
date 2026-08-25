/// Recovery records contributing to one exposed PDF value.
public struct PDFRecoveryProvenance: Sendable, Hashable {
  /// Ordered recovery records affecting the value.
  public let records: [PDFRecoveryRecordIdentifier]
  /// The least authoritative classification among those records.
  public let classification: PDFRecoveryClassification

  /// Creates recovery provenance.
  public init(
    records: [PDFRecoveryRecordIdentifier],
    classification: PDFRecoveryClassification
  ) {
    self.records = records
    self.classification = classification
  }
}
