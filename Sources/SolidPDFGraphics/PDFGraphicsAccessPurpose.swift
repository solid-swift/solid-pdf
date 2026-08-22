/// The caller's semantic reason for interpreting PDF page graphics.
public enum PDFGraphicsAccessPurpose: Sendable, Hashable {
  /// Display the document.
  case viewing
  /// Extract document content.
  case extraction
  /// Extract content for accessibility.
  case accessibilityExtraction
  /// Produce ordinary printed output.
  case printing
  /// Produce high-quality printed output.
  case highQualityPrinting
}
