import Foundation

/// A structurally parsed PDF signature value without cryptographic validation.
public struct PDFSignature: Sendable, Hashable {
  /// Signed source ranges in declared order.
  public let byteRanges: [PDFSourceRange]
  /// The decoded signature container bytes.
  public let contents: Data
  /// The preferred signature handler.
  public let filter: PDFName?
  /// The signature encoding or subfilter.
  public let subfilter: PDFName?
  /// The signer's stated reason.
  public let reason: String?
  /// The PDF date string retained without interpretation.
  public let signingTime: PDFString?
  /// Optional seed-value or document permission metadata.
  public let permissions: PDFObject?
  /// The original signature dictionary.
  public let rawDictionary: [PDFName: PDFObject]
  /// The revision defining the signature value.
  public let definingRevision: PDFRevisionIdentifier
}
