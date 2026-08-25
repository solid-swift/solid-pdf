/// Options enabling malformed-PDF recovery after strict parsing fails.
public struct PDFRecoveryOptions: Sendable, Hashable {
  /// The permitted recovery tier.
  public var policy: PDFRecoveryPolicy
  /// Recovery-specific resource limits.
  public var limits: PDFRecoveryLimits

  /// Creates recovery options.
  public init(
    policy: PDFRecoveryPolicy = .structural,
    limits: PDFRecoveryLimits = .init()
  ) {
    self.policy = policy
    self.limits = limits
  }
}
