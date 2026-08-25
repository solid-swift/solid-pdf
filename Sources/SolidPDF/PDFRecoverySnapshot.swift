package struct PDFRecoverySnapshot: Sendable {
  package let source: PDFRecoverySource
  package let policy: PDFRecoveryPolicy
  package let limits: PDFRecoveryLimits
  package let parsingLimits: PDFParsingLimits
  package let evidence: PDFRecoveryEvidence
  package let model: PDFRecoveryModel
  package let generation: Int
}

package struct PDFRecoveryModel: Sendable, Hashable {
  package var headerOffset: Int64?
  package var version: PDFFileVersion?
  package var endOffset: Int64?
  package var acceptsMissingEndOfFile = false
  package var startCrossReferenceOffset: Int64?
  package var acceptsMismatchedFooter = false
  package var crossReferenceFailure: PDFParsingDiagnostic?
  package var reconstructedCrossReference: PDFRecoveredCrossReferencePlan?

  package func contains(fact: String) -> Bool {
    switch fact {
    case "header": headerOffset != nil
    case "end-of-file": endOffset != nil
    case "startxref": startCrossReferenceOffset != nil
    case "reconstructed-xref": reconstructedCrossReference != nil
    default: false
    }
  }

  package mutating func apply(_ mutation: PDFRecoveryMutation) {
    switch mutation {
    case .header(let offset, let version):
      headerOffset = offset
      self.version = version
    case .endOfFile(let offset, let acceptsMissingMarker):
      endOffset = offset
      acceptsMissingEndOfFile = acceptsMissingMarker
    case .startCrossReference(let offset, let acceptsMismatchedFooter):
      startCrossReferenceOffset = offset
      self.acceptsMismatchedFooter = acceptsMismatchedFooter
    case .reconstructedCrossReference(let plan):
      reconstructedCrossReference = plan
    }
  }
}
