import SolidPDF
import SolidPostScript

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
  /// One-based transmitted page ordinals to retain, or `nil` for all pages.
  public var selectedPageOrdinals: Set<Int>?
  /// Labels assigned to retained pages in output order.
  public var pageLabels: [String]
  /// Optional crop rectangles assigned to retained pages in output order.
  public var cropBoxes: [GraphicsRect?]

  /// Creates rendering options.
  public init(
    version: PDFVersion = .v2_0,
    fallbackPolicy: PDFFallbackPolicy = .exact,
    fallbackDPI: Double = 300,
    compressionLevel: Int = -1,
    limits: PDFWritingLimits = .init(),
    metadata: PDFDocumentMetadata = .init(),
    selectedPageOrdinals: Set<Int>? = nil,
    pageLabels: [String] = [],
    cropBoxes: [GraphicsRect?] = []
  ) {
    self.version = version
    self.fallbackPolicy = fallbackPolicy
    self.fallbackDPI = fallbackDPI
    self.compressionLevel = compressionLevel
    self.limits = limits
    self.metadata = metadata
    self.selectedPageOrdinals = selectedPageOrdinals
    self.pageLabels = pageLabels
    self.cropBoxes = cropBoxes
  }
}
