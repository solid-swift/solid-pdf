/// A non-secret request for another PDF password candidate.
public struct PDFPasswordRequest: Sendable, Hashable {
  /// The one-based provider attempt number.
  public let attempt: Int
  /// The validated, non-secret encryption configuration.
  public let encryption: PDFEncryptionDescription

  package init(attempt: Int, encryption: PDFEncryptionDescription) {
    self.attempt = attempt
    self.encryption = encryption
  }
}
