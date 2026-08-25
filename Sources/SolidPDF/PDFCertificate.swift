import Foundation

/// A portable immutable X.509 certificate description.
public struct PDFCertificate: Sendable, Hashable {
  /// The exact DER certificate bytes.
  public let derRepresentation: Data
  /// The unsigned big-endian serial-number bytes.
  public let serialNumber: Data
  /// The printable subject distinguished name.
  public let subject: String
  /// The printable issuer distinguished name.
  public let issuer: String
  /// The beginning of the certificate validity interval.
  public let notValidBefore: Date
  /// The end of the certificate validity interval.
  public let notValidAfter: Date
  /// The SHA-256 digest of the exact DER certificate.
  public let sha256Fingerprint: Data

  /// Creates a portable certificate description.
  public init(
    derRepresentation: Data,
    serialNumber: Data,
    subject: String,
    issuer: String,
    notValidBefore: Date,
    notValidAfter: Date,
    sha256Fingerprint: Data
  ) {
    self.derRepresentation = derRepresentation
    self.serialNumber = serialNumber
    self.subject = subject
    self.issuer = issuer
    self.notValidBefore = notValidBefore
    self.notValidAfter = notValidAfter
    self.sha256Fingerprint = sha256Fingerprint
  }
}
