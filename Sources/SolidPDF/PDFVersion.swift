/// A supported Portable Document Format version.
public enum PDFVersion: String, Sendable, Hashable, CaseIterable {
  /// ISO 32000-1 PDF 1.7 compatibility output.
  case v1_7 = "1.7"
  /// ISO 32000-2 PDF 2.0 output.
  case v2_0 = "2.0"
}
