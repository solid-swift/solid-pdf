/// The source of an effective PDF page attribute.
public enum PDFPageAttributeOrigin: Sendable, Hashable {
  /// The attribute was defined by the page itself.
  case page(PDFObjectReference)
  /// The attribute was inherited from the nearest defining page-tree ancestor.
  case ancestor(PDFObjectReference)
  /// The attribute was supplied by a PDF-defined default.
  case defaulted
}

/// A normalized page attribute together with its provenance.
public struct PDFPageAttribute<Value: Sendable & Hashable>: Sendable, Hashable {
  /// The effective attribute value.
  public let value: Value
  /// The value's page, ancestor, or default origin.
  public let origin: PDFPageAttributeOrigin

  /// Creates an attributed page value.
  public init(value: Value, origin: PDFPageAttributeOrigin) {
    self.value = value
    self.origin = origin
  }
}
