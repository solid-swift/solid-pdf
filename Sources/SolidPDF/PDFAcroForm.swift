/// The document-level AcroForm configuration and root fields.
public struct PDFAcroForm: Sendable, Hashable {
  public let fields: [PDFFormFieldIdentifier]
  public let defaultResources: [PDFName: PDFObject]?
  public let defaultAppearance: PDFString?
  public let justification: Int
  public let calculationOrder: [PDFFormFieldIdentifier]
  public let signatureFlags: Int
  public let needsAppearances: Bool
  public let xfa: PDFObject?
  public let rawDictionary: [PDFName: PDFObject]
  public let definingRevision: PDFRevisionIdentifier
}
