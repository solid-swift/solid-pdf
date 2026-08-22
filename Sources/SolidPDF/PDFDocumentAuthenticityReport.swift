/// A document-wide authenticity report with independent validation dimensions.
public struct PDFDocumentAuthenticityReport: Sendable, Hashable {
  /// The revision through which later changes were evaluated.
  public let revision: PDFRevisionIdentifier
  /// Signatures visible in the selected revision.
  public let signatures: [PDFSignature]
  /// Validation results in signature discovery order.
  public let validationResults: [PDFSignatureValidationResult]
  /// Document permissions established by the authenticated security handler.
  public let documentPermissions: PDFPermissionSet?
  /// Nonfatal parsing, trust, or compatibility diagnostics.
  public let diagnostics: [PDFParsingDiagnostic]

  /// Creates an authenticity report.
  public init(
    revision: PDFRevisionIdentifier,
    signatures: [PDFSignature],
    validationResults: [PDFSignatureValidationResult],
    documentPermissions: PDFPermissionSet?,
    diagnostics: [PDFParsingDiagnostic] = []
  ) {
    self.revision = revision
    self.signatures = signatures
    self.validationResults = validationResults
    self.documentPermissions = documentPermissions
    self.diagnostics = diagnostics
  }
}
