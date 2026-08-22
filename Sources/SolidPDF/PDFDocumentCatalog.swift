/// A validated PDF document catalog and its page-tree root.
public struct PDFDocumentCatalog: Sendable, Hashable {
  /// The catalog's indirect object reference.
  public let reference: PDFObjectReference
  /// The catalog dictionary as represented in the selected revision.
  public let rawDictionary: [PDFName: PDFObject]
  /// The revision that defines the resolved catalog object.
  public let definingRevision: PDFRevisionIdentifier
  /// The indirect root of the page tree.
  public let pageTreeRoot: PDFObjectReference
  /// The page count declared by the page-tree root.
  public let declaredPageCount: Int
  /// The effective PDF version after applying the catalog's optional `/Version`.
  public let effectiveVersion: PDFFileVersion

  package init(
    reference: PDFObjectReference,
    rawDictionary: [PDFName: PDFObject],
    definingRevision: PDFRevisionIdentifier,
    pageTreeRoot: PDFObjectReference,
    declaredPageCount: Int,
    effectiveVersion: PDFFileVersion
  ) {
    self.reference = reference
    self.rawDictionary = rawDictionary
    self.definingRevision = definingRevision
    self.pageTreeRoot = pageTreeRoot
    self.declaredPageCount = declaredPageCount
    self.effectiveVersion = effectiveVersion
  }
}
