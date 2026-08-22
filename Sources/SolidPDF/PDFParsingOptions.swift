/// Options controlling strict PDF parsing and resource use.
public struct PDFParsingOptions: Sendable, Hashable {
  /// Resource limits applied throughout parsing and resolution.
  public var limits: PDFParsingLimits
  /// Size of each bounded source window.
  public var sourceWindowByteCount: Int

  /// Creates PDF parsing options.
  public init(limits: PDFParsingLimits = .init(), sourceWindowByteCount: Int = 64 * 1_024) {
    self.limits = limits
    self.sourceWindowByteCount = sourceWindowByteCount
  }
}
