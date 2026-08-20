import SolidPDF

/// Options controlling PostScript-to-PDF rendering.
public struct PDFRenderOptions: Sendable, Hashable {
  /// The emitted PDF version.
  public var version: PDFVersion
  /// Exact fallback behavior.
  public var fallbackPolicy: PDFFallbackPolicy
  /// Resolution used for raster fallback.
  public var fallbackDPI: Double
  /// Zlib compression level used for streams.
  public var compressionLevel: Int
  /// PDF writer resource limits.
  public var limits: PDFWritingLimits
  /// Optional deterministic document metadata.
  public var metadata: PDFDocumentMetadata

  /// Creates rendering options.
  public init(
    version: PDFVersion = .v2_0,
    fallbackPolicy: PDFFallbackPolicy = .exact,
    fallbackDPI: Double = 300,
    compressionLevel: Int = -1,
    limits: PDFWritingLimits = .init(),
    metadata: PDFDocumentMetadata = .init()
  ) {
    self.version = version
    self.fallbackPolicy = fallbackPolicy
    self.fallbackDPI = fallbackDPI
    self.compressionLevel = compressionLevel
    self.limits = limits
    self.metadata = metadata
  }
}
