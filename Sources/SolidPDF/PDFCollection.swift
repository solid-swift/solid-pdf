/// The initial presentation requested by a PDF portable collection.
public enum PDFCollectionView: Sendable, Hashable {
  case details
  case tile
  case hidden
  case unknown(PDFName)
}

/// One field declared by a portable-collection schema.
public struct PDFCollectionSchemaField: Sendable, Hashable {
  public let name: PDFName
  public let subtype: PDFName
  public let displayName: String
  public let order: Int
  public let isVisible: Bool
  public let isEditable: Bool
  public let rawDictionary: [PDFName: PDFObject]

  public init(
    name: PDFName,
    subtype: PDFName,
    displayName: String,
    order: Int = 0,
    isVisible: Bool = true,
    isEditable: Bool = false,
    rawDictionary: [PDFName: PDFObject]
  ) {
    self.name = name
    self.subtype = subtype
    self.displayName = displayName
    self.order = order
    self.isVisible = isVisible
    self.isEditable = isEditable
    self.rawDictionary = rawDictionary
  }
}

/// Collection item values associated with one embedded file.
public struct PDFCollectionItem: Sendable, Hashable {
  public let fileSpecification: PDFFileSpecificationIdentifier
  public let values: [PDFName: PDFObject]

  public init(fileSpecification: PDFFileSpecificationIdentifier, values: [PDFName: PDFObject]) {
    self.fileSpecification = fileSpecification
    self.values = values
  }
}

/// The stable sort declaration of a portable collection.
public struct PDFCollectionSort: Sendable, Hashable {
  public let fields: [PDFName]
  public let ascending: [Bool]

  public init(fields: [PDFName], ascending: [Bool]) {
    self.fields = fields
    self.ascending = ascending
  }
}

/// Inert portable-collection metadata from a PDF catalog.
public struct PDFCollection: Sendable, Hashable {
  public let view: PDFCollectionView
  public let initialDocument: PDFString?
  public let schema: [PDFName: PDFCollectionSchemaField]
  public let items: [PDFCollectionItem]
  public let sort: PDFCollectionSort?
  public let rawDictionary: [PDFName: PDFObject]
  public let definingRevision: PDFRevisionIdentifier

  public init(
    view: PDFCollectionView,
    initialDocument: PDFString? = nil,
    schema: [PDFName: PDFCollectionSchemaField] = [:],
    items: [PDFCollectionItem] = [],
    sort: PDFCollectionSort? = nil,
    rawDictionary: [PDFName: PDFObject],
    definingRevision: PDFRevisionIdentifier
  ) {
    self.view = view
    self.initialDocument = initialDocument
    self.schema = schema
    self.items = items
    self.sort = sort
    self.rawDictionary = rawDictionary
    self.definingRevision = definingRevision
  }
}
