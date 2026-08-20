/// A deterministic request to retain selected glyphs from one font face.
public struct FontSubsetRequest: Sendable, Hashable {
  /// Original glyph indexes requested by the document.
  public let glyphIndexes: [UInt32]
  /// Whether TrueType instructions and supporting hint tables should be retained.
  public let preservesHints: Bool

  /// Creates a normalized subset request.
  public init(glyphIndexes: some Sequence<UInt32>, preservesHints: Bool = true) {
    self.glyphIndexes = Array(Set(glyphIndexes).union([0])).sorted()
    self.preservesHints = preservesHints
  }
}
