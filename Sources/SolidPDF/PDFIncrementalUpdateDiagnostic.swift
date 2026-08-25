/// A nonfatal diagnostic produced while appending a PDF revision.
public struct PDFIncrementalUpdateDiagnostic: Sendable, Hashable {
  /// Stable diagnostic categories.
  public enum Kind: Sendable, Hashable {
    /// Existing linearization information no longer describes the updated file.
    case linearizationInvalidated
    /// Inert form actions were intentionally not executed.
    case actionsNotExecuted
    /// An existing signature now has a later document revision.
    case signatureModification
    /// A form value and its appearance were normalized together.
    case appearanceRegenerated
  }

  /// The diagnostic category.
  public let kind: Kind
  /// A human-readable explanation.
  public let message: String

  /// Creates an incremental-update diagnostic.
  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }
}
