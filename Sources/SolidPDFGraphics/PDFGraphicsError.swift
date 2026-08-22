import SolidPDF

/// A failure while interpreting PDF page content into graphics events.
public enum PDFGraphicsError: Error, Sendable, Hashable {
  /// Content syntax or graphics-object state is malformed.
  case malformedContent(message: String, operatorName: String?, location: PDFContentLocation)
  /// A well-formed feature cannot be represented by this interpreter tranche.
  case unsupported(PDFGraphicsUnsupportedFeature, location: PDFContentLocation)
  /// The authenticated document permissions deny the requested purpose.
  case permissionDenied(PDFGraphicsAccessPurpose)
  /// Target construction, event processing, or finalization failed.
  case targetFailure(String)
  /// A configured interpretation limit was exceeded.
  case limitExceeded(String, location: PDFContentLocation?)
}
