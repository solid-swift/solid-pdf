import Foundation

/// A lazily decoded file embedded in a PDF document.
public struct PDFEmbeddedFile: Sendable, Hashable {
  /// The exact EmbeddedFiles name-tree key, when present.
  public let nameTreeKey: PDFString?
  /// The owning file specification.
  public let fileSpecification: PDFFileSpecification
  /// The embedded-file stream.
  public let stream: PDFStreamObject
  /// The stream subtype, commonly an encoded media type.
  public let subtype: PDFName?
  /// The declared decoded byte count.
  public let declaredSize: Int?
  /// The declared MD5 checksum bytes.
  public let checksum: Data?
  /// The declared creation date.
  public let creationDate: PDFDate?
  /// The declared modification date.
  public let modificationDate: PDFDate?
  /// The raw embedded-file parameter dictionary.
  public let parameters: [PDFName: PDFObject]
  /// The revision defining the embedded stream.
  public let definingRevision: PDFRevisionIdentifier

  public init(
    nameTreeKey: PDFString? = nil,
    fileSpecification: PDFFileSpecification,
    stream: PDFStreamObject,
    subtype: PDFName? = nil,
    declaredSize: Int? = nil,
    checksum: Data? = nil,
    creationDate: PDFDate? = nil,
    modificationDate: PDFDate? = nil,
    parameters: [PDFName: PDFObject] = [:],
    definingRevision: PDFRevisionIdentifier
  ) {
    self.nameTreeKey = nameTreeKey
    self.fileSpecification = fileSpecification
    self.stream = stream
    self.subtype = subtype
    self.declaredSize = declaredSize
    self.checksum = checksum
    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.parameters = parameters
    self.definingRevision = definingRevision
  }
}
