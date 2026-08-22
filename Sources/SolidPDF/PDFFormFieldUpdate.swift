/// One field mutation in an atomic AcroForm transaction.
public struct PDFFormFieldUpdate: Sendable, Hashable {
  /// The terminal field to update.
  public let field: PDFFormFieldIdentifier
  /// The semantic replacement value.
  public let value: PDFFormFieldUpdateValue
  /// Rich-text handling for text and choice fields.
  public let richText: PDFRichTextUpdate

  /// Creates one field update.
  public init(
    field: PDFFormFieldIdentifier,
    value: PDFFormFieldUpdateValue,
    richText: PDFRichTextUpdate = .remove
  ) {
    self.field = field
    self.value = value
    self.richText = richText
  }
}
