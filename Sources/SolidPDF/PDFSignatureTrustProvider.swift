import Foundation

/// Immutable inputs supplied to a signature trust provider.
public struct PDFSignatureTrustRequest: Sendable, Hashable {
  /// The certificate whose trust is being evaluated.
  public let leaf: PDFCertificate
  /// Untrusted intermediate certificates available from the document and caller.
  public let intermediates: [PDFCertificate]
  /// The validation instant selected for this role.
  public let validationTime: Date
  /// Whether this is a signer or timestamp-authority chain.
  public let role: PDFSignatureTrustRole
  /// Bounded DER CRL or OCSP evidence.
  public let revocationEvidence: [Data]

  /// Creates a trust request.
  public init(
    leaf: PDFCertificate,
    intermediates: [PDFCertificate],
    validationTime: Date,
    role: PDFSignatureTrustRole,
    revocationEvidence: [Data] = []
  ) {
    self.leaf = leaf
    self.intermediates = intermediates
    self.validationTime = validationTime
    self.role = role
    self.revocationEvidence = revocationEvidence
  }
}

/// A trust provider's bounded, portable result.
public struct PDFSignatureTrustResult: Sendable, Hashable {
  /// Certificate trust status.
  public let trust: PDFSignatureTrustStatus
  /// The selected chain, leaf first.
  public let chain: [PDFCertificate]
  /// Revocation status.
  public let revocation: PDFSignatureRevocationStatus
  /// Nonsecret provider diagnostics.
  public let diagnostics: [PDFParsingDiagnostic]

  /// Creates a trust result.
  public init(
    trust: PDFSignatureTrustStatus,
    chain: [PDFCertificate] = [],
    revocation: PDFSignatureRevocationStatus = .notChecked,
    diagnostics: [PDFParsingDiagnostic] = []
  ) {
    self.trust = trust
    self.chain = chain
    self.revocation = revocation
    self.diagnostics = diagnostics
  }
}

/// Evaluates a certificate chain without receiving document or file capabilities.
public protocol PDFSignatureTrustProvider: Sendable {
  /// Evaluates one signer or timestamp-authority certificate chain.
  func evaluate(_ request: PDFSignatureTrustRequest) async throws -> PDFSignatureTrustResult
}
