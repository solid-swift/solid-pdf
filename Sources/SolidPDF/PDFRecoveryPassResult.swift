package enum PDFRecoveryPassResult: Sendable {
  case noMatch
  case proposals([PDFRecoveryProposal])
  case unrecoverable(PDFParsingDiagnostic)
}
