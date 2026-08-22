/// The role assigned to a PDF signature dictionary.
public enum PDFSignatureKind: Sendable, Hashable {
  /// An ordinary approval signature.
  case approval
  /// A certification signature carrying a DocMDP transform.
  case certification
  /// A document timestamp signature.
  case documentTimestamp
  /// A usage-rights signature.
  case usageRights
  /// An extension role identified by its PDF name.
  case other(PDFName)
}
