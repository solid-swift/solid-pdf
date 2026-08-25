package struct PDFRecoveredCrossReferencePlan: Sendable, Hashable {
  package let version: PDFFileVersion
  package let representation: PDFCrossReferenceRepresentation
  package let entries: [Int: PDFCrossReferenceEntry]
  package let trailer: [PDFName: PDFObject]
  package let boundaries: [Int: PDFRecoveredObjectBoundary]
  package let startOffset: Int64
  package let endOffset: Int64
}
