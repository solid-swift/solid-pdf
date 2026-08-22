/// A nonfatal observation produced while interpreting PDF graphics.
public struct PDFGraphicsDiagnostic: Sendable, Hashable {
  /// Diagnostic severity.
  public enum Severity: Sendable, Hashable {
    /// Information about a standards-defined no-op or fallback.
    case information
    /// A portable fallback was selected without changing visible semantics.
    case warning
  }

  /// Stable diagnostic identifier.
  public let identifier: String
  /// Human-readable diagnostic text.
  public let message: String
  /// Diagnostic severity.
  public let severity: Severity
  /// Source location, when the diagnostic belongs to a content operation.
  public let location: PDFContentLocation?

  /// Creates a diagnostic.
  public init(
    identifier: String,
    message: String,
    severity: Severity,
    location: PDFContentLocation? = nil
  ) {
    self.identifier = identifier
    self.message = message
    self.severity = severity
    self.location = location
  }
}
