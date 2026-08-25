/// Whether a recovered document supports an authority-sensitive operation.
public enum PDFRecoveryOperationEligibility: Sendable, Hashable {
  /// Recovery preserved the byte-exact facts required by the operation.
  case eligible
  /// Recovery cannot establish the facts required by the operation.
  case ineligible(reason: String)
}
