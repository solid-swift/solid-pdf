/// The storage location from which an indirect PDF object was resolved.
public enum PDFObjectProvenance: Sendable, Hashable {
  /// The object is stored directly in the PDF file.
  case file
  /// The object is stored at an index in an object stream.
  case objectStream(container: PDFObjectReference, index: Int)
}
