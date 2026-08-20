/// A nonfatal diagnostic produced while constructing a PDF document.
public struct PDFDiagnostic: Sendable, Hashable {
  /// A stable diagnostic category.
  public enum Kind: Sendable, Hashable {
    /// A requested feature was represented using a compatible older construct.
    case compatibilityDowngrade
    /// Metadata could not be represented and was omitted.
    case discardedMetadata
    /// A renderer supplied an informational diagnostic.
    case rendering
  }

  /// The diagnostic category.
  public let kind: Kind
  /// A human-readable explanation.
  public let message: String

  /// Creates a diagnostic.
  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }
}
