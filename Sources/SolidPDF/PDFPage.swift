/// A structurally validated PDF page with effective inherited attributes.
public struct PDFPage: Sendable, Hashable {
  /// The zero-based page index in the selected revision.
  public let index: Int
  /// The page object's indirect reference.
  public let reference: PDFObjectReference
  /// The page dictionary without inherited values inserted.
  public let rawDictionary: [PDFName: PDFObject]
  /// The revision that defines the effective page object.
  public let definingRevision: PDFRevisionIdentifier
  /// Page-tree ancestors from the root through the immediate parent.
  public let ancestorReferences: [PDFObjectReference]
  /// The effective, whole inherited resource dictionary.
  public let resources: PDFPageAttribute<[PDFName: PDFObject]>
  /// Normalized page geometry and provenance.
  public let geometry: PDFPageGeometry
  /// Ordered content streams. Empty represents an empty page.
  public let contentStreams: [PDFStreamObject]

  package init(
    index: Int,
    reference: PDFObjectReference,
    rawDictionary: [PDFName: PDFObject],
    definingRevision: PDFRevisionIdentifier,
    ancestorReferences: [PDFObjectReference],
    resources: PDFPageAttribute<[PDFName: PDFObject]>,
    geometry: PDFPageGeometry,
    contentStreams: [PDFStreamObject] = []
  ) {
    self.index = index
    self.reference = reference
    self.rawDictionary = rawDictionary
    self.definingRevision = definingRevision
    self.ancestorReferences = ancestorReferences
    self.resources = resources
    self.geometry = geometry
    self.contentStreams = contentStreams
  }
}
