/// One resolved AcroForm field with inherited semantics applied.
public struct PDFFormField: Sendable, Hashable {
  public let identifier: PDFFormFieldIdentifier
  public let parent: PDFFormFieldIdentifier?
  public let children: [PDFFormFieldIdentifier]
  public let widgets: [PDFWidget]
  public let type: PDFFormFieldType?
  public let flags: PDFFormFieldFlags
  public let partialName: String?
  public let fullyQualifiedName: String?
  public let alternateName: String?
  public let mappingName: String?
  public let value: PDFFormValue?
  public let defaultValue: PDFFormValue?
  public let options: [PDFObject]
  /// The inherited maximum character count, when present.
  public let maximumLength: Int?
  /// The selected zero-based choice-option indices declared by this field.
  public let selectedOptionIndices: [Int]
  public let defaultAppearance: PDFString?
  public let justification: Int
  public let resources: [PDFName: PDFObject]?
  public let actions: [PDFName: PDFAction]
  public let richTextValue: PDFString?
  public let signature: PDFSignature?
  public let rawDictionary: [PDFName: PDFObject]
  public let definingRevision: PDFRevisionIdentifier
}
