/// The complete, ordered account of repairs used to open a malformed PDF.
public struct PDFRecoveryReport: Sendable, Hashable {
  /// The enabled recovery tier.
  public let policy: PDFRecoveryPolicy
  /// The diagnostic that caused strict opening to fail.
  public let strictFailure: PDFParsingDiagnostic
  /// Applied repairs and inferences in coordinator order.
  public let records: [PDFRecoveryRecord]
  /// Damage retained for inspection but not repaired.
  public let unresolvedDamage: [PDFParsingDiagnostic]
  /// Whether incremental writing can preserve authoritative structure.
  public let incrementalWriting: PDFRecoveryOperationEligibility
  /// Whether signature coverage and modifications remain authoritative.
  public let signatureValidation: PDFRecoveryOperationEligibility

  package init(
    policy: PDFRecoveryPolicy,
    strictFailure: PDFParsingDiagnostic,
    records: [PDFRecoveryRecord],
    unresolvedDamage: [PDFParsingDiagnostic] = [],
    incrementalWriting: PDFRecoveryOperationEligibility,
    signatureValidation: PDFRecoveryOperationEligibility
  ) {
    self.policy = policy
    self.strictFailure = strictFailure
    self.records = records
    self.unresolvedDamage = unresolvedDamage
    self.incrementalWriting = incrementalWriting
    self.signatureValidation = signatureValidation
  }
}
