import Foundation

/// A metadata-only description of one embedded asset.
public struct PDFEmbeddedFileSummary: Sendable, Hashable {
  /// The file specification identity.
  public let identifier: PDFFileSpecificationIdentifier?
  /// The exact EmbeddedFiles name-tree key.
  public let nameTreeKey: PDFString?
  /// The decoded Unicode display filename, when declared.
  public let filename: String?
  /// The embedded stream subtype.
  public let subtype: PDFName?
  /// The declared decoded size.
  public let declaredSize: Int?
  /// The declared checksum without reading the attachment body.
  public let checksum: Data?
  /// The revision defining the embedded stream.
  public let revision: PDFRevisionIdentifier

  /// Creates an embedded-file summary.
  public init(
    identifier: PDFFileSpecificationIdentifier?,
    nameTreeKey: PDFString?,
    filename: String?,
    subtype: PDFName?,
    declaredSize: Int?,
    checksum: Data?,
    revision: PDFRevisionIdentifier
  ) {
    self.identifier = identifier
    self.nameTreeKey = nameTreeKey
    self.filename = filename
    self.subtype = subtype
    self.declaredSize = declaredSize
    self.checksum = checksum
    self.revision = revision
  }
}

/// A signature summary that omits container and signature bytes.
public struct PDFSignatureDescriptor: Sendable, Hashable {
  /// The signature identity.
  public let identifier: PDFSignatureIdentifier?
  /// The signature role.
  public let kind: PDFSignatureKind
  /// The PDF signature subfilter.
  public let subfilter: PDFName?
  /// The signed revision, when established.
  public let signedRevision: PDFRevisionIdentifier?
  /// Printable signer subjects from matched certificates.
  public let signerSubjects: [String]
  /// Signature transforms in declaration order.
  public let transforms: [PDFSignatureTransform]

  /// Creates a byte-free signature descriptor.
  public init(
    identifier: PDFSignatureIdentifier?,
    kind: PDFSignatureKind,
    subfilter: PDFName?,
    signedRevision: PDFRevisionIdentifier?,
    signerSubjects: [String],
    transforms: [PDFSignatureTransform]
  ) {
    self.identifier = identifier
    self.kind = kind
    self.subfilter = subfilter
    self.signedRevision = signedRevision
    self.signerSubjects = signerSubjects
    self.transforms = transforms
  }
}

/// A bounded structural inventory that never decodes attachment bodies.
public struct PDFDocumentAssetInventory: Sendable, Hashable {
  /// Reconciled document metadata.
  public let metadata: PDFMetadata
  /// Embedded-file summaries in deterministic name-tree order.
  public let embeddedFiles: [PDFEmbeddedFileSummary]
  /// Every associated-file relationship.
  public let associatedFiles: [PDFAssociatedFile]
  /// Portable collection metadata, when present.
  public let collection: PDFCollection?
  /// Signature descriptors without `/Contents` bytes.
  public let signatures: [PDFSignatureDescriptor]

  /// Creates a structural asset inventory.
  public init(
    metadata: PDFMetadata,
    embeddedFiles: [PDFEmbeddedFileSummary],
    associatedFiles: [PDFAssociatedFile],
    collection: PDFCollection?,
    signatures: [PDFSignatureDescriptor]
  ) {
    self.metadata = metadata
    self.embeddedFiles = embeddedFiles
    self.associatedFiles = associatedFiles
    self.collection = collection
    self.signatures = signatures
  }
}
