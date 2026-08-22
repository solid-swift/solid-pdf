import Foundation

/// A document-scoped logical structure-element identifier.
public struct PDFStructureElementIdentifier: Sendable, Hashable, Comparable {
  /// The indirect object containing the structure element.
  public let reference: PDFObjectReference

  public init(reference: PDFObjectReference) { self.reference = reference }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.reference < rhs.reference }
}

/// A namespace used by PDF 2.0 structure types and attributes.
public struct PDFStructureNamespace: Sendable, Hashable {
  /// The namespace dictionary's indirect reference.
  public let reference: PDFObjectReference
  /// The namespace URI.
  public let namespace: String
  /// The optional schema location.
  public let schema: PDFObject?
  /// The original namespace dictionary.
  public let rawDictionary: [PDFName: PDFObject]
}

/// A marked-content reference in a logical structure element.
public struct PDFStructureMarkedContentReference: Sendable, Hashable {
  /// The content-stream-local marked-content identifier.
  public let markedContentIdentifier: Int
  /// The page containing the marked content, when specified or inherited.
  public let page: PDFObjectReference?
  /// The content stream owning the MCID, or `nil` for page contents.
  public let stream: PDFObjectReference?
}

/// An object reference in a logical structure element.
public struct PDFStructureObjectReference: Sendable, Hashable {
  /// The referenced annotation or XObject.
  public let object: PDFObjectReference
  /// The page containing the object, when specified or inherited.
  public let page: PDFObjectReference?
}

/// One child in structure-defined logical order.
public enum PDFStructureChild: Sendable, Hashable {
  /// A child structure element.
  case element(PDFStructureElementIdentifier)
  /// Marked content selected by MCID.
  case markedContent(PDFStructureMarkedContentReference)
  /// A referenced content object.
  case object(PDFStructureObjectReference)
}

/// A resolved logical structure element.
public struct PDFStructureElement: Sendable, Hashable {
  public let identifier: PDFStructureElementIdentifier
  public let structureType: PDFName
  public let namespace: PDFObjectReference?
  public let parent: PDFObjectReference
  public let page: PDFObjectReference?
  public let children: [PDFStructureChild]
  public let identifierBytes: Data?
  public let title: String?
  public let language: String?
  public let alternateDescription: String?
  public let replacementText: String?
  public let expansion: String?
  public let classNames: [PDFName]
  public let attributes: [PDFObject]
  public let rawDictionary: [PDFName: PDFObject]
  public let definingRevision: PDFRevisionIdentifier
}

/// The resolved root and shared mappings of a document's logical structure.
public struct PDFStructureTree: Sendable, Hashable {
  public let reference: PDFObjectReference
  public let children: [PDFStructureChild]
  public let roleMap: [PDFName: PDFName]
  public let classMap: [PDFName: [PDFObject]]
  public let namespaces: [PDFStructureNamespace]
  public let parentTreeNextKey: Int?
  public let rawDictionary: [PDFName: PDFObject]
  public let definingRevision: PDFRevisionIdentifier
}
