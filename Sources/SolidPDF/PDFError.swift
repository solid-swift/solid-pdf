/// An error raised while constructing or publishing a PDF document.
public enum PDFError: Error, Sendable, Hashable {
  /// A PDF object contains an unsupported or invalid value.
  case invalidObject
  /// A requested object reference was not reserved or was already defined.
  case invalidReference
  /// The document contains an unresolved indirect reference.
  case unresolvedReference(PDFObjectReference)
  /// A configured writer limit was exceeded.
  case limitExceeded
  /// The requested value is unavailable in the selected PDF version.
  case incompatibleVersion
  /// Stream compression failed.
  case compressionFailure
  /// The output sink failed.
  case outputFailure
  /// Publishing would replace an existing destination.
  case outputExists
  /// The writer was already finalized or abandoned.
  case writerFinished
}
