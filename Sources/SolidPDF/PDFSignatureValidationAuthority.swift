/// Whether signature conclusions remain authoritative after PDF recovery.
public enum PDFSignatureValidationAuthority: Sendable, Hashable {
  /// The signature and revision structure were resolved strictly or byte-exactly.
  case authoritative
  /// Recovery affected facts required for an authoritative conclusion.
  case limitedByRecovery([PDFRecoveryRecordIdentifier])
}
