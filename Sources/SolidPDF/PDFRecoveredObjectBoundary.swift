package struct PDFRecoveredObjectBoundary: Sendable, Hashable {
  package let reference: PDFObjectReference
  package let sourceRange: PDFSourceRange
  package let streamRange: PDFSourceRange?
  package let hasEndObject: Bool
  package let requiresRecoveredParsing: Bool
  package let repair: PDFRecoveredBoundaryRepair?
}

package struct PDFRecoveredBoundaryRepair: Sendable, Hashable {
  package let kind: PDFRecoveryKind
  package let classification: PDFRecoveryClassification
  package let sourceRanges: [PDFSourceRange]
  package let message: String
}
