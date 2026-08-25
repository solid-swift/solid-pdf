import Foundation

/// A document-scoped identity for a PDF file specification.
public struct PDFFileSpecificationIdentifier: Sendable, Hashable {
  public let reference: PDFObjectReference?
  public let revision: PDFRevisionIdentifier
  package let directObject: PDFObject?

  package init(reference: PDFObjectReference?, revision: PDFRevisionIdentifier, directObject: PDFObject? = nil) {
    self.reference = reference
    self.revision = revision
    self.directObject = directObject
  }
}

/// An inert PDF file specification that is never interpreted as a host path.
public struct PDFFileSpecification: Sendable, Hashable {
  public let identifier: PDFFileSpecificationIdentifier
  public let fileSystem: PDFName?
  public let filename: PDFString?
  public let unicodeFilename: String?
  public let identifiers: [PDFString]?
  public let isVolatile: Bool
  public let description: String?
  public let relatedFiles: PDFObject?
  public let collectionItem: [PDFName: PDFObject]?
  public let embeddedFileEntries: [PDFName: PDFObject]
  public let rawObject: PDFObject
  public let definingRevision: PDFRevisionIdentifier

  public init(
    identifier: PDFFileSpecificationIdentifier,
    fileSystem: PDFName? = nil,
    filename: PDFString? = nil,
    unicodeFilename: String? = nil,
    identifiers: [PDFString]? = nil,
    isVolatile: Bool = false,
    description: String? = nil,
    relatedFiles: PDFObject? = nil,
    collectionItem: [PDFName: PDFObject]? = nil,
    embeddedFileEntries: [PDFName: PDFObject] = [:],
    rawObject: PDFObject,
    definingRevision: PDFRevisionIdentifier
  ) {
    self.identifier = identifier
    self.fileSystem = fileSystem
    self.filename = filename
    self.unicodeFilename = unicodeFilename
    self.identifiers = identifiers
    self.isVolatile = isVolatile
    self.description = description
    self.relatedFiles = relatedFiles
    self.collectionItem = collectionItem
    self.embeddedFileEntries = embeddedFileEntries
    self.rawObject = rawObject
    self.definingRevision = definingRevision
  }
}
