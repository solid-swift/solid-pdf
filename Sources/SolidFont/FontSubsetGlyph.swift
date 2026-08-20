/// One original glyph retained in an embedded font subset.
public struct FontSubsetGlyph: Sendable, Hashable {
  /// The glyph index in the original face.
  public let originalIndex: UInt32
  /// The densely assigned glyph index in the subset.
  public let subsetIndex: UInt32
  /// The PostScript glyph name, when the source supplies one.
  public let name: String?
  /// The source CID, when the source is CID-keyed.
  public let cid: UInt32?
  /// The horizontal advance in source design units.
  public let advance: Double
  /// The source design-space bounds, when known.
  public let bounds: FontBounds?

  /// Creates subset glyph metadata.
  public init(
    originalIndex: UInt32,
    subsetIndex: UInt32,
    name: String? = nil,
    cid: UInt32? = nil,
    advance: Double = 0,
    bounds: FontBounds? = nil
  ) {
    self.originalIndex = originalIndex
    self.subsetIndex = subsetIndex
    self.name = name
    self.cid = cid
    self.advance = advance
    self.bounds = bounds
  }
}
