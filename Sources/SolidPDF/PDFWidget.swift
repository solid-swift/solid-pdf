/// A widget annotation associated with an AcroForm field.
public struct PDFWidget: Sendable, Hashable {
  public let annotationIdentifier: PDFAnnotationIdentifier
  public let pageReference: PDFObjectReference
  public let rectangle: PDFRectangle
  public let appearanceState: PDFName?
  public let rawDictionary: [PDFName: PDFObject]
}
