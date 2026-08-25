/// The location of a revision's standard security dictionary.
public enum PDFEncryptionLocator: Sendable, Hashable {
  /// The encryption dictionary is embedded directly in the trailer.
  case direct
  /// The encryption dictionary is stored in an ordinary indirect object.
  case indirect(PDFObjectReference)
}
