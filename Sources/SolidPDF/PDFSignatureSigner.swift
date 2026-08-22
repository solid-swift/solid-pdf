import Foundation

/// A signer declared by a CMS signature container.
public struct PDFSignatureSigner: Sendable, Hashable {
  /// The signer's issuer name and serial number, when used by the container.
  public let issuerAndSerialNumber: PDFSignatureIssuerAndSerialNumber?
  /// The signer's subject-key identifier, when used by the container.
  public let subjectKeyIdentifier: Data?
  /// The message digest algorithm.
  public let digestAlgorithm: PDFDigestAlgorithm
  /// The public-key signature algorithm.
  public let signatureAlgorithm: PDFSignatureAlgorithm
  /// The raw signature value.
  public let signature: Data
  /// The authenticated message digest attribute, when present.
  public let messageDigest: Data?
  /// The authenticated signing time, when present.
  public let signingTime: Date?
  /// The certificate matched to this signer, when present.
  public let certificate: PDFCertificate?
  /// Unknown signed attribute object identifiers retained for inspection.
  public let unknownSignedAttributeIdentifiers: [String]
  /// Unknown unsigned attribute object identifiers retained for inspection.
  public let unknownUnsignedAttributeIdentifiers: [String]

  /// Creates portable signer metadata.
  public init(
    issuerAndSerialNumber: PDFSignatureIssuerAndSerialNumber? = nil,
    subjectKeyIdentifier: Data? = nil,
    digestAlgorithm: PDFDigestAlgorithm,
    signatureAlgorithm: PDFSignatureAlgorithm,
    signature: Data,
    messageDigest: Data? = nil,
    signingTime: Date? = nil,
    certificate: PDFCertificate? = nil,
    unknownSignedAttributeIdentifiers: [String] = [],
    unknownUnsignedAttributeIdentifiers: [String] = []
  ) {
    self.issuerAndSerialNumber = issuerAndSerialNumber
    self.subjectKeyIdentifier = subjectKeyIdentifier
    self.digestAlgorithm = digestAlgorithm
    self.signatureAlgorithm = signatureAlgorithm
    self.signature = signature
    self.messageDigest = messageDigest
    self.signingTime = signingTime
    self.certificate = certificate
    self.unknownSignedAttributeIdentifiers = unknownSignedAttributeIdentifiers
    self.unknownUnsignedAttributeIdentifiers = unknownUnsignedAttributeIdentifiers
  }
}

/// A CMS issuer-and-serial signer identifier.
public struct PDFSignatureIssuerAndSerialNumber: Sendable, Hashable {
  /// The exact DER issuer distinguished name.
  public let issuerDER: Data
  /// The unsigned big-endian certificate serial number.
  public let serialNumber: Data

  /// Creates an issuer-and-serial identifier.
  public init(issuerDER: Data, serialNumber: Data) {
    self.issuerDER = issuerDER
    self.serialNumber = serialNumber
  }
}
