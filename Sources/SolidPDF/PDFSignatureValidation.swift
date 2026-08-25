import Foundation

/// The cryptographic integrity result for one signature.
public enum PDFSignatureIntegrityStatus: Sendable, Hashable {
  /// The digest and public-key signature are valid.
  case valid
  /// The signature is cryptographically invalid.
  case invalid(reason: String)
  /// The declared algorithm is not supported by this implementation.
  case unsupported(algorithm: String)
}

/// The certificate trust result for one signer.
public enum PDFSignatureTrustStatus: Sendable, Hashable {
  /// No trust provider was supplied.
  case notEvaluated
  /// A chain terminates at an explicitly trusted anchor.
  case trusted
  /// No acceptable chain terminates at a trusted anchor.
  case untrusted
  /// Trust could not be determined because the provider failed or lacked evidence.
  case indeterminate(String)
}

/// The revocation status determined from bounded offline evidence.
public enum PDFSignatureRevocationStatus: Sendable, Hashable {
  /// No revocation evaluation was requested or possible.
  case notChecked
  /// Evidence establishes that the certificate was not revoked at the validation time.
  case good
  /// Evidence establishes that the certificate was revoked.
  case revoked
  /// Evidence does not establish a status.
  case unknown
  /// Available evidence was outside its validity interval.
  case stale
}

/// The role for which a certificate chain is evaluated.
public enum PDFSignatureTrustRole: Sendable, Hashable {
  /// A document signer.
  case signer
  /// An RFC 3161 timestamp authority.
  case timestampAuthority
}

/// Coverage of the signed source revision and later bytes.
public struct PDFSignatureCoverage: Sendable, Hashable {
  /// Whether declared ranges exactly cover the signed revision except for `/Contents`.
  public let coversSignedRevision: Bool
  /// The revision identified as the signed revision.
  public let signedRevision: PDFRevisionIdentifier?
  /// Revisions appended after the signature was created.
  public let laterRevisions: [PDFRevisionIdentifier]
  /// Bytes after the final recognized revision boundary.
  public let unsignedTrailingByteCount: Int64
  /// Unaccounted gaps other than the lexical `/Contents` token.
  public let unaccountedGaps: [PDFSourceRange]

  /// Creates a coverage result.
  public init(
    coversSignedRevision: Bool,
    signedRevision: PDFRevisionIdentifier?,
    laterRevisions: [PDFRevisionIdentifier],
    unsignedTrailingByteCount: Int64,
    unaccountedGaps: [PDFSourceRange]
  ) {
    self.coversSignedRevision = coversSignedRevision
    self.signedRevision = signedRevision
    self.laterRevisions = laterRevisions
    self.unsignedTrailingByteCount = unsignedTrailingByteCount
    self.unaccountedGaps = unaccountedGaps
  }
}

/// Whether post-signing changes comply with signature transforms.
public enum PDFSignatureModificationStatus: Sendable, Hashable {
  /// No later object definitions were observed.
  case unchanged
  /// Every observed change is permitted by the applicable transforms.
  case permitted(changedObjects: [PDFObjectReference])
  /// At least one observed change violates an applicable transform.
  case prohibited(changedObjects: [PDFObjectReference])
  /// The changes could not be classified authoritatively.
  case indeterminate(changedObjects: [PDFObjectReference], reason: String)
}

/// Timestamp evidence associated with a signature.
public enum PDFSignatureTimestampStatus: Sendable, Hashable {
  /// No authenticated timestamp is present.
  case absent
  /// A CMS signing time is authenticated by the signer but not independently trusted.
  case signingTime(Date)
  /// An RFC 3161 timestamp is cryptographically and trust validated.
  case trusted(Date)
  /// Timestamp evidence is malformed, invalid, or untrusted.
  case invalid(String)
}

/// Options controlling one signature validation.
public struct PDFSignatureValidationOptions: Sendable {
  /// A caller-selected offline or external trust evaluator.
  public var trustProvider: (any PDFSignatureTrustProvider)?
  /// The chain-validation instant. `nil` selects authenticated timestamp or current time.
  public var validationTime: Date?
  /// Whether later revisions are classified against signature transforms.
  public var validatesModifications: Bool

  /// Creates signature validation options.
  public init(
    trustProvider: (any PDFSignatureTrustProvider)? = nil,
    validationTime: Date? = nil,
    validatesModifications: Bool = true
  ) {
    self.trustProvider = trustProvider
    self.validationTime = validationTime
    self.validatesModifications = validatesModifications
  }
}

/// The independent validation dimensions for one PDF signature.
public struct PDFSignatureValidationResult: Sendable, Hashable {
  /// The validated signature identity.
  public let signature: PDFSignatureIdentifier?
  /// Exact source coverage.
  public let coverage: PDFSignatureCoverage
  /// Cryptographic integrity.
  public let integrity: PDFSignatureIntegrityStatus
  /// Certificate trust.
  public let trust: PDFSignatureTrustStatus
  /// Revocation status.
  public let revocation: PDFSignatureRevocationStatus
  /// Timestamp status.
  public let timestamp: PDFSignatureTimestampStatus
  /// Modification-policy status.
  public let modifications: PDFSignatureModificationStatus
  /// The chain selected by the trust provider, leaf first.
  public let certificateChain: [PDFCertificate]
  /// Nonfatal validation diagnostics.
  public let diagnostics: [PDFParsingDiagnostic]
  /// Whether coverage and modification conclusions remain authoritative.
  public let authority: PDFSignatureValidationAuthority

  /// Creates a validation result.
  public init(
    signature: PDFSignatureIdentifier?,
    coverage: PDFSignatureCoverage,
    integrity: PDFSignatureIntegrityStatus,
    trust: PDFSignatureTrustStatus,
    revocation: PDFSignatureRevocationStatus,
    timestamp: PDFSignatureTimestampStatus,
    modifications: PDFSignatureModificationStatus,
    certificateChain: [PDFCertificate] = [],
    diagnostics: [PDFParsingDiagnostic] = [],
    authority: PDFSignatureValidationAuthority = .authoritative
  ) {
    self.signature = signature
    self.coverage = coverage
    self.integrity = integrity
    self.trust = trust
    self.revocation = revocation
    self.timestamp = timestamp
    self.modifications = modifications
    self.certificateChain = certificateChain
    self.diagnostics = diagnostics
    self.authority = authority
  }
}
