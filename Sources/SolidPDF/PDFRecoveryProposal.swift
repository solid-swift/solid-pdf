package struct PDFRecoveryProposal: Sendable, Hashable {
  package let fact: String
  package let kind: PDFRecoveryKind
  package let classification: PDFRecoveryClassification
  package let sourceRanges: [PDFSourceRange]
  package let object: PDFObjectReference?
  package let message: String
  package let mutation: PDFRecoveryMutation

  package init(
    fact: String,
    kind: PDFRecoveryKind,
    classification: PDFRecoveryClassification,
    sourceRanges: [PDFSourceRange],
    object: PDFObjectReference? = nil,
    message: String,
    mutation: PDFRecoveryMutation
  ) {
    self.fact = fact
    self.kind = kind
    self.classification = classification
    self.sourceRanges = sourceRanges
    self.object = object
    self.message = message
    self.mutation = mutation
  }
}

package enum PDFRecoveryMutation: Sendable, Hashable {
  case header(offset: Int64, version: PDFFileVersion)
  case endOfFile(offset: Int64, acceptsMissingMarker: Bool)
  case startCrossReference(offset: Int64, acceptsMismatchedFooter: Bool)
  case reconstructedCrossReference(PDFRecoveredCrossReferencePlan)
}
