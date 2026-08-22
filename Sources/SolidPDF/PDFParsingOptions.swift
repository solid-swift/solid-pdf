/// Options controlling strict PDF parsing and resource use.
public struct PDFParsingOptions: Sendable, Hashable {
  /// Resource limits applied throughout parsing and resolution.
  public var limits: PDFParsingLimits
  /// Size of each bounded source window.
  public var sourceWindowByteCount: Int
  /// Maximum bytes emitted by one decoded-stream iteration.
  public var decodedStreamChunkByteCount: Int
  /// Whether compatibility aliases are accepted in ordinary stream dictionaries.
  public var acceptsStreamFilterAbbreviations: Bool

  /// Creates PDF parsing options.
  public init(
    limits: PDFParsingLimits = .init(),
    sourceWindowByteCount: Int = 64 * 1_024,
    decodedStreamChunkByteCount: Int = 64 * 1_024,
    acceptsStreamFilterAbbreviations: Bool = false
  ) {
    self.limits = limits
    self.sourceWindowByteCount = sourceWindowByteCount
    self.decodedStreamChunkByteCount = decodedStreamChunkByteCount
    self.acceptsStreamFilterAbbreviations = acceptsStreamFilterAbbreviations
  }
}
