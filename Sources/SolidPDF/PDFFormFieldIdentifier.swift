/// The document-scoped identity of an indirect AcroForm field.
public struct PDFFormFieldIdentifier: Sendable, Hashable, Comparable {
  /// The field's indirect object reference.
  public let reference: PDFObjectReference

  public init(reference: PDFObjectReference) { self.reference = reference }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.reference < rhs.reference }
}
