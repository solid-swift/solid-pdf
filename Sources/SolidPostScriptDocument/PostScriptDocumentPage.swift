/// DSC metadata for one declared document page.
public struct PostScriptDocumentPage: Sendable, Hashable {
  public let label: String
  public let ordinal: Int
  public let bounds: PostScriptDocumentBounds?
  public let byteRange: Range<Int>?

  /// Creates page metadata.
  public init(label: String, ordinal: Int, bounds: PostScriptDocumentBounds?, byteRange: Range<Int>?) {
    self.label = label
    self.ordinal = ordinal
    self.bounds = bounds
    self.byteRange = byteRange
  }
}
