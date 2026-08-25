/// Pages selected for PDF graphics interpretation.
public enum PDFGraphicsPageSelection: Sendable, Hashable {
  /// Interpret every page in document order.
  case all
  /// Interpret caller-ordered zero-based page indices, including repetitions.
  case indices([Int])
}
