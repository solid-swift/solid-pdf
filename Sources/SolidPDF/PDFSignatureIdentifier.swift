/// An opaque document-scoped signature identity.
public struct PDFSignatureIdentifier: Sendable, Hashable {
  /// The indirect signature dictionary reference.
  public let reference: PDFObjectReference
  /// The revision in which the signature dictionary is effective.
  public let revision: PDFRevisionIdentifier

  /// Creates an identity from an indirect signature dictionary and revision.
  public init(reference: PDFObjectReference, revision: PDFRevisionIdentifier) {
    self.reference = reference
    self.revision = revision
  }
}
