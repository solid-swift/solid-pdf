/// The resolved value of an indirect PDF object.
public enum PDFResolvedObject: Sendable, Hashable {
  /// A non-stream PDF object.
  case value(PDFObject)
  /// A PDF stream whose encoded bytes remain lazily source-backed.
  case stream(PDFStreamObject)
}
