import Foundation

/// A content-stream-local marked-content identifier.
public struct GraphicsMarkedContentIdentifier: Sendable, Hashable {
  /// The owning content-stream resource.
  public let owner: GraphicsResourceIdentifier
  /// The nonnegative MCID within that owner.
  public let value: Int

  public init(owner: GraphicsResourceIdentifier, value: Int) {
    self.owner = owner
    self.value = value
  }
}

/// Replacement text associated with physical document content.
public struct GraphicsTextReplacement: Sendable, Hashable {
  public enum Provenance: Sendable, Hashable {
    case markedContent
    case structureElement(GraphicsResourceIdentifier)
  }

  public let text: String
  public let provenance: Provenance

  public init(text: String, provenance: Provenance) {
    self.text = text
    self.provenance = provenance
  }
}

/// Standard artifact metadata carried by a marked-content scope.
public struct GraphicsArtifactDescription: Sendable, Hashable {
  public let type: Data?
  public let subtype: Data?
  public let bounds: GraphicsRect?
  public let attachments: [Data]

  public init(
    type: Data? = nil,
    subtype: Data? = nil,
    bounds: GraphicsRect? = nil,
    attachments: [Data] = []
  ) {
    self.type = type
    self.subtype = subtype
    self.bounds = bounds
    self.attachments = attachments
  }
}

/// Portable properties associated with a marked-content scope or point.
public struct GraphicsMarkedContentProperties: Sendable, Hashable {
  public let identifier: GraphicsMarkedContentIdentifier?
  public let language: String?
  public let replacement: GraphicsTextReplacement?
  public let alternateDescription: String?
  public let expansion: String?
  public let artifact: GraphicsArtifactDescription?
  public let values: [Data: GraphicsSemanticValue]

  public init(
    identifier: GraphicsMarkedContentIdentifier? = nil,
    language: String? = nil,
    replacement: GraphicsTextReplacement? = nil,
    alternateDescription: String? = nil,
    expansion: String? = nil,
    artifact: GraphicsArtifactDescription? = nil,
    values: [Data: GraphicsSemanticValue] = [:]
  ) {
    self.identifier = identifier
    self.language = language
    self.replacement = replacement
    self.alternateDescription = alternateDescription
    self.expansion = expansion
    self.artifact = artifact
    self.values = values
  }
}

/// One active marked-content scope in outer-to-inner order.
public struct GraphicsMarkedContentScope: Sendable, Hashable {
  public let resourceIdentifier: GraphicsResourceIdentifier
  public let tag: Data
  public let properties: GraphicsMarkedContentProperties
  /// The evaluated visibility of content within this scope.
  public let visibility: GraphicsContentVisibility

  public init(
    resourceIdentifier: GraphicsResourceIdentifier = .anonymous,
    tag: Data,
    properties: GraphicsMarkedContentProperties = .init(),
    visibility: GraphicsContentVisibility = .visible
  ) {
    self.resourceIdentifier = resourceIdentifier
    self.tag = tag
    self.properties = properties
    self.visibility = visibility
  }
}

/// An ordered marked-content boundary or point operation.
public enum GraphicsMarkedContentOperation: Sendable, Hashable {
  case begin(GraphicsMarkedContentScope)
  case end(GraphicsMarkedContentScope)
  case point(GraphicsMarkedContentScope)
}
