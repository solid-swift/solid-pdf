/// Immutable DSC metadata extracted without modifying executable bytes.
public struct PostScriptDocumentMetadata: Sendable, Hashable {
  public let kind: PostScriptDocumentKind
  public let title: String?
  public let creator: String?
  public let version: String?
  public let bounds: PostScriptDocumentBounds?
  public let pages: [PostScriptDocumentPage]
  public let declaredPageCount: Int?
  public let warnings: [String]
  public let programByteRange: Range<Int>
}
