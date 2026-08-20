/// The document raster background.
public enum PostScriptDocumentBackground: Sendable, Hashable {
  case white
  case transparent
  case rgba(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
}
