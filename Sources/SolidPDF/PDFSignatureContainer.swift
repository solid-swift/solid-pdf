import Foundation

/// A bounded, parsed PDF signature container.
public struct PDFSignatureContainer: Sendable, Hashable {
  /// The container representation selected by the PDF subfilter.
  public let format: PDFSignatureContainerFormat
  /// The exact DER bytes after removal of permitted PDF zero padding.
  public let derRepresentation: Data
  /// The CMS encapsulated-content type object identifier, when applicable.
  public let contentTypeIdentifier: String?
  /// The CMS encapsulated content, when present.
  public let encapsulatedContent: Data?
  /// The declared signers in encoded order.
  public let signers: [PDFSignatureSigner]
  /// Certificates embedded in the container.
  public let certificates: [PDFCertificate]
  /// Embedded RFC 3161 timestamp-token containers.
  public let timestampTokens: [PDFSignatureContainer]

  /// Creates a portable signature-container description.
  public init(
    format: PDFSignatureContainerFormat,
    derRepresentation: Data,
    contentTypeIdentifier: String? = nil,
    encapsulatedContent: Data? = nil,
    signers: [PDFSignatureSigner] = [],
    certificates: [PDFCertificate] = [],
    timestampTokens: [PDFSignatureContainer] = []
  ) {
    self.format = format
    self.derRepresentation = derRepresentation
    self.contentTypeIdentifier = contentTypeIdentifier
    self.encapsulatedContent = encapsulatedContent
    self.signers = signers
    self.certificates = certificates
    self.timestampTokens = timestampTokens
  }
}
