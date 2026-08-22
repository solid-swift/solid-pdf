/// Non-secret metadata describing a PDF standard security handler.
public struct PDFEncryptionDescription: Sendable, Hashable {
  /// The security-handler version (`/V`).
  public let version: Int
  /// The standard-handler revision (`/R`).
  public let revision: Int
  /// The file-encryption key length in bits.
  public let keyBitCount: Int
  /// Whether document metadata is encrypted.
  public let encryptsMetadata: Bool
  /// The configured crypt filters in deterministic name order.
  public let cryptFilters: [PDFCryptFilterDescription]

  package init(
    version: Int,
    revision: Int,
    keyBitCount: Int,
    encryptsMetadata: Bool,
    cryptFilters: [PDFCryptFilterDescription]
  ) {
    self.version = version
    self.revision = revision
    self.keyBitCount = keyBitCount
    self.encryptsMetadata = encryptsMetadata
    self.cryptFilters = cryptFilters
  }
}
