import Foundation

/// Optional deterministic PDF document metadata.
public struct PDFDocumentMetadata: Sendable, Hashable {
  /// The document title.
  public var title: String?
  /// The creating application or DSC creator.
  public var creator: String?
  /// The producing library name.
  public var producer: String?
  /// An explicit creation date.
  public var creationDate: Date?
  /// An explicit modification date.
  public var modificationDate: Date?

  /// Creates document metadata.
  public init(
    title: String? = nil,
    creator: String? = nil,
    producer: String? = "SolidPDF",
    creationDate: Date? = nil,
    modificationDate: Date? = nil
  ) {
    self.title = title
    self.creator = creator
    self.producer = producer
    self.creationDate = creationDate
    self.modificationDate = modificationDate
  }
}
