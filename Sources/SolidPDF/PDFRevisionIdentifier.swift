import Foundation

/// An opaque identifier for one revision of an opened PDF document.
///
/// Revision identifiers are scoped to their originating document. Passing an identifier to a
/// different document produces ``PDFParsingError/unknownRevision(_:)``.
public struct PDFRevisionIdentifier: Sendable, Hashable, Comparable {
  /// The zero-based chronological position of the revision.
  public let ordinal: Int

  private let documentIdentifier: UUID

  package init(documentIdentifier: UUID, ordinal: Int) {
    self.documentIdentifier = documentIdentifier
    self.ordinal = ordinal
  }

  public static func < (lhs: PDFRevisionIdentifier, rhs: PDFRevisionIdentifier) -> Bool {
    if lhs.documentIdentifier == rhs.documentIdentifier { return lhs.ordinal < rhs.ordinal }
    return lhs.documentIdentifier.uuidString < rhs.documentIdentifier.uuidString
  }
}
