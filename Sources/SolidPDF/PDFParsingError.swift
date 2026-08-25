/// A feature intentionally unavailable in the current PDF reader tranche.
public enum PDFUnsupportedFeature: Sendable, Hashable {
  /// The input contains one or more earlier document revisions.
  case incrementalUpdates
  /// The input is encrypted.
  case encryption
  /// A structural stream uses an unsupported filter or filter configuration.
  case structuralStreamFilter
  /// Stream data is stored outside the PDF and no provider authorized access.
  case externalStream
  /// A stream requests decryption before the security-handler tranche is available.
  case encryptionFilter
  /// A stream uses JPEG 2000 data.
  case jpxDecode
  /// A stream uses JBIG2 data.
  case jbig2Decode
  /// A stream names an unknown or unavailable filter.
  case streamFilter(PDFName)
  /// The document uses a public-key security handler.
  case publicKeySecurity
  /// The document selects PDF's unpublished `/V 3` encryption algorithm.
  case unpublishedEncryptionAlgorithm
  /// The document selects an unsupported security handler.
  case securityHandler(PDFName)
  /// The document selects an unsupported crypt method.
  case cryptMethod(PDFName)
  /// A signature selects an unsupported digest or public-key algorithm.
  case signatureAlgorithm(String)
}

/// An error raised while opening or resolving a PDF document.
public enum PDFParsingError: Error, Sendable, Hashable {
  /// The input violates PDF lexical, object, or cross-reference syntax.
  case malformed(PDFParsingDiagnostic)
  /// The input ends before a required value is complete.
  case truncated(PDFParsingDiagnostic)
  /// A configured parsing or storage limit was exceeded.
  case limitExceeded(PDFParsingDiagnostic)
  /// The document requires functionality not enabled in this tranche.
  case unsupported(PDFUnsupportedFeature, PDFParsingDiagnostic)
  /// The source could not provide the requested bytes.
  case sourceFailure(PDFParsingDiagnostic)
  /// Resolving indirect references encountered a cycle.
  case referenceCycle([PDFObjectReference])
  /// A requested indirect reference is absent or has the wrong generation.
  case unresolvedReference(PDFObjectReference)
  /// A revision identifier does not belong to the document.
  case unknownRevision(PDFRevisionIdentifier)
  /// A requested zero-based page index is outside the selected revision's page tree.
  case pageIndexOutOfRange(Int)
  /// The encrypted document requires a password provider.
  case authenticationRequired(PDFEncryptionDescription)
  /// None of the supplied passwords authenticated the document.
  case invalidPassword(PDFEncryptionDescription)
  /// The password provider failed without exposing its error details.
  case authenticationFailure(PDFParsingDiagnostic)
  /// The document has already been closed.
  case documentClosed
}
