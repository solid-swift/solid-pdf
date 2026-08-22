/// The relationship of an associated file to its owning PDF object.
public enum PDFAssociatedFileRelationship: Sendable, Hashable {
  case source
  case data
  case alternative
  case supplement
  case encryptedPayload
  case formData
  case schema
  case unspecified
  case other(PDFName)

  package init(_ name: PDFName?) {
    self = switch name {
    case "Source": .source
    case "Data": .data
    case "Alternative": .alternative
    case "Supplement": .supplement
    case "EncryptedPayload": .encryptedPayload
    case "FormData": .formData
    case "Schema": .schema
    case "Unspecified", nil: .unspecified
    case .some(let value): .other(value)
    }
  }
}

/// The PDF object that declares an associated-file relationship.
public enum PDFAssociatedFileOwner: Sendable, Hashable {
  case catalog(PDFObjectReference)
  case annotation(PDFAnnotationIdentifier)
  case object(PDFObjectReference)
}

/// One inert associated-file declaration.
public struct PDFAssociatedFile: Sendable, Hashable {
  public let fileSpecification: PDFFileSpecification
  public let relationship: PDFAssociatedFileRelationship
  public let owner: PDFAssociatedFileOwner
  public let revision: PDFRevisionIdentifier

  public init(
    fileSpecification: PDFFileSpecification,
    relationship: PDFAssociatedFileRelationship,
    owner: PDFAssociatedFileOwner,
    revision: PDFRevisionIdentifier
  ) {
    self.fileSpecification = fileSpecification
    self.relationship = relationship
    self.owner = owner
    self.revision = revision
  }
}
