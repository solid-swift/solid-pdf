/// Options controlling deterministic PDF serialization.
public struct PDFWritingOptions: Sendable, Hashable {
  /// The emitted PDF version.
  public var version: PDFVersion
  /// The zlib compression level used for compressed streams.
  public var compressionLevel: Int
  /// Resource limits applied during construction.
  public var limits: PDFWritingLimits

  /// Creates writing options.
  public init(
    version: PDFVersion = .v2_0,
    compressionLevel: Int = -1,
    limits: PDFWritingLimits = .init()
  ) {
    self.version = version
    self.compressionLevel = compressionLevel
    self.limits = limits
  }
}
