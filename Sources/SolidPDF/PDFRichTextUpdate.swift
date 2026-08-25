/// Controls retained rich-text source when assigning a plain AcroForm value.
public enum PDFRichTextUpdate: Sendable, Hashable {
  /// Removes a potentially stale `/RV` value.
  case remove
  /// Replaces `/RV` with exact caller-provided bytes without interpreting them.
  case replace(PDFString)
}
