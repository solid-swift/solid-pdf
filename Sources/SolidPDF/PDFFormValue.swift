/// A normalized AcroForm field value that preserves its PDF representation.
public enum PDFFormValue: Sendable, Hashable {
  case string(PDFString)
  case name(PDFName)
  case strings([PDFString])
  case null
  case other(PDFObject)
}
