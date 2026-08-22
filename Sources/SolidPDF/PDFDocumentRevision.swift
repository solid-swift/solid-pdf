/// Immutable metadata describing one chronological revision of a PDF document.
public struct PDFDocumentRevision: Sendable, Hashable {
  /// The document-scoped revision identifier.
  public let identifier: PDFRevisionIdentifier
  /// The revision's cross-reference representation.
  public let representation: PDFCrossReferenceRepresentation
  /// The absolute offset named by this revision's `startxref` entry.
  public let startCrossReferenceOffset: Int64
  /// The absolute offset immediately after this revision's `%%EOF` marker.
  public let endOffset: Int64
  /// The revision trailer, excluding cross-reference stream-only structural keys.
  public let trailer: [PDFName: PDFObject]
  /// The catalog reference effective for this revision.
  public let root: PDFObjectReference
  /// The optional information dictionary reference effective for this revision.
  public let info: PDFObjectReference?
  /// The optional two-part file identifier effective for this revision.
  public let fileIdentifier: [PDFString]?
  /// The encryption dictionary value effective for this revision.
  public let encryption: PDFObject?

  package init(
    identifier: PDFRevisionIdentifier,
    representation: PDFCrossReferenceRepresentation,
    startCrossReferenceOffset: Int64,
    endOffset: Int64,
    trailer: [PDFName: PDFObject],
    root: PDFObjectReference,
    info: PDFObjectReference?,
    fileIdentifier: [PDFString]?,
    encryption: PDFObject?
  ) {
    self.identifier = identifier
    self.representation = representation
    self.startCrossReferenceOffset = startCrossReferenceOffset
    self.endOffset = endOffset
    self.trailer = trailer
    self.root = root
    self.info = info
    self.fileIdentifier = fileIdentifier
    self.encryption = encryption
  }
}
