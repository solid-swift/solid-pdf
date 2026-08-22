/// The document-scoped identity of an indirect annotation object.
public struct PDFAnnotationIdentifier: Sendable, Hashable, Comparable {
  /// The annotation's indirect object reference.
  public let reference: PDFObjectReference

  /// Creates an annotation identifier.
  public init(reference: PDFObjectReference) {
    self.reference = reference
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.reference < rhs.reference
  }
}
