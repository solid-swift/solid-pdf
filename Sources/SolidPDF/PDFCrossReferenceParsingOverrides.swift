struct PDFCrossReferenceParsingOverrides: Sendable {
  let headerOffset: Int64
  let version: PDFFileVersion
  let latestCrossReferenceOffset: Int64
  let acceptsMismatchedFooter: Bool
  let acceptsMissingEndOfFile: Bool
  let recoveryReport: PDFRecoveryReport
}
