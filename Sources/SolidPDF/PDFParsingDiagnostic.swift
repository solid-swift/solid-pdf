/// Source context attached to a PDF parsing failure or warning.
public struct PDFParsingDiagnostic: Sendable, Hashable {
  /// The absolute byte offset associated with the diagnostic.
  public let offset: Int64
  /// The enclosing indirect object, when known.
  public let object: PDFObjectReference?
  /// A stable human-readable explanation.
  public let message: String

  /// Creates parsing diagnostic context.
  public init(offset: Int64, object: PDFObjectReference? = nil, message: String) {
    self.offset = offset
    self.object = object
    self.message = message
  }
}
