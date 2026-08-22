import Foundation

/// The source from which a document metadata value was obtained.
public enum PDFMetadataSource: Sendable, Hashable {
  case informationDictionary
  case xmp
}

/// One metadata value together with its authoritative source.
public struct PDFMetadataProperty<Value: Sendable & Hashable>: Sendable, Hashable {
  public let value: Value
  public let source: PDFMetadataSource

  public init(value: Value, source: PDFMetadataSource) {
    self.value = value
    self.source = source
  }
}

/// Standard reconciled PDF metadata fields.
public struct PDFMetadataFields: Sendable, Hashable {
  public let title: PDFMetadataProperty<String>?
  public let author: PDFMetadataProperty<String>?
  public let subject: PDFMetadataProperty<String>?
  public let keywords: PDFMetadataProperty<String>?
  public let creator: PDFMetadataProperty<String>?
  public let producer: PDFMetadataProperty<String>?
  public let creationDate: PDFMetadataProperty<PDFDate>?
  public let modificationDate: PDFMetadataProperty<PDFDate>?

  public init(
    title: PDFMetadataProperty<String>? = nil,
    author: PDFMetadataProperty<String>? = nil,
    subject: PDFMetadataProperty<String>? = nil,
    keywords: PDFMetadataProperty<String>? = nil,
    creator: PDFMetadataProperty<String>? = nil,
    producer: PDFMetadataProperty<String>? = nil,
    creationDate: PDFMetadataProperty<PDFDate>? = nil,
    modificationDate: PDFMetadataProperty<PDFDate>? = nil
  ) {
    self.title = title
    self.author = author
    self.subject = subject
    self.keywords = keywords
    self.creator = creator
    self.producer = producer
    self.creationDate = creationDate
    self.modificationDate = modificationDate
  }
}

/// One namespace-qualified XMP property retained from an RDF packet.
public struct PDFMetadataPropertyValue: Sendable, Hashable {
  public let qualifiedName: String
  public let language: String?
  public let value: String

  public init(qualifiedName: String, language: String? = nil, value: String) {
    self.qualifiedName = qualifiedName
    self.language = language
    self.value = value
  }
}

/// The exact decoded XMP packet and its bounded property projection.
public struct PDFXMPPacket: Sendable, Hashable {
  public let bytes: Data
  public let properties: [PDFMetadataPropertyValue]
  public let streamReference: PDFObjectReference
  public let definingRevision: PDFRevisionIdentifier

  public init(
    bytes: Data,
    properties: [PDFMetadataPropertyValue],
    streamReference: PDFObjectReference,
    definingRevision: PDFRevisionIdentifier
  ) {
    self.bytes = bytes
    self.properties = properties
    self.streamReference = streamReference
    self.definingRevision = definingRevision
  }
}

/// A nonfatal discrepancy encountered while reconciling metadata sources.
public struct PDFMetadataDiagnostic: Sendable, Hashable {
  public let field: String?
  public let message: String

  public init(field: String? = nil, message: String) {
    self.field = field
    self.message = message
  }
}

/// Revision-specific document metadata from Info and XMP sources.
public struct PDFMetadata: Sendable, Hashable {
  public let fields: PDFMetadataFields
  public let informationDictionary: [PDFName: PDFObject]?
  public let informationRevision: PDFRevisionIdentifier?
  public let customInformation: [PDFName: PDFString]
  public let xmp: PDFXMPPacket?
  public let diagnostics: [PDFMetadataDiagnostic]

  public init(
    fields: PDFMetadataFields,
    informationDictionary: [PDFName: PDFObject]? = nil,
    informationRevision: PDFRevisionIdentifier? = nil,
    customInformation: [PDFName: PDFString] = [:],
    xmp: PDFXMPPacket? = nil,
    diagnostics: [PDFMetadataDiagnostic] = []
  ) {
    self.fields = fields
    self.informationDictionary = informationDictionary
    self.informationRevision = informationRevision
    self.customInformation = customInformation
    self.xmp = xmp
    self.diagnostics = diagnostics
  }
}
