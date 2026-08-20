/// Selects the rectangle used for document raster output.
public enum PostScriptDocumentCropMode: Sendable, Hashable {
  case automatic
  case media
  case boundingBox
}
