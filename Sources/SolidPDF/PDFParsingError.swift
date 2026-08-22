/// A feature intentionally unavailable in the current PDF reader tranche.
public enum PDFUnsupportedFeature: Sendable, Hashable {
  /// The input contains one or more earlier document revisions.
  case incrementalUpdates
  /// The input is encrypted.
  case encryption
  /// A structural stream uses an unsupported filter or filter configuration.
  case structuralStreamFilter
}

/// An error raised while opening or resolving a PDF document.
public enum PDFParsingError: Error, Sendable, Hashable {
  /// The input violates PDF lexical, object, or cross-reference syntax.
  case malformed(PDFParsingDiagnostic)
  /// The input ends before a required value is complete.
  case truncated(PDFParsingDiagnostic)
  /// A configured parsing or storage limit was exceeded.
  case limitExceeded(PDFParsingDiagnostic)
  /// The document requires functionality not enabled in this tranche.
  case unsupported(PDFUnsupportedFeature, PDFParsingDiagnostic)
  /// The source could not provide the requested bytes.
  case sourceFailure(PDFParsingDiagnostic)
  /// Resolving indirect references encountered a cycle.
  case referenceCycle([PDFObjectReference])
  /// A requested indirect reference is absent or has the wrong generation.
  case unresolvedReference(PDFObjectReference)
  /// The document has already been closed.
  case documentClosed
}
