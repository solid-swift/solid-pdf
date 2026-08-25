package struct PDFRecoveredObjectBoundary: Sendable, Hashable {
  package let reference: PDFObjectReference
  package let sourceRange: PDFSourceRange
  package let streamRange: PDFSourceRange?
  package let hasEndObject: Bool
}
