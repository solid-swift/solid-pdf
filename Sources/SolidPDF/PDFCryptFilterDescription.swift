/// A validated PDF crypt-filter configuration.
public struct PDFCryptFilterDescription: Sendable, Hashable {
  /// The crypt method selected by the filter.
  public enum Method: Sendable, Hashable {
    /// No encryption is applied.
    case identity
    /// RC4 encryption with a legacy object key.
    case rc4
    /// AES-128 CBC encryption with a legacy object key.
    case aes128
    /// AES-256 CBC encryption with the file key.
    case aes256
  }

  /// The crypt-filter name.
  public let name: PDFName
  /// The selected crypt method.
  public let method: Method
  /// The key length in bytes.
  public let keyByteCount: Int

  package init(name: PDFName, method: Method, keyByteCount: Int) {
    self.name = name
    self.method = method
    self.keyByteCount = keyByteCount
  }
}
