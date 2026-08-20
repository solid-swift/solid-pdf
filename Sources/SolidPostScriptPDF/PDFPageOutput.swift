import SolidPDF
import SolidPostScript

/// How one transmitted PDF page was represented.
public enum PDFPageFallbackDisposition: Sendable, Hashable {
  /// All effects were represented as native PDF graphics.
  case vector
  /// One or more independent effects were rasterized locally.
  case localized
  /// The complete page was rasterized to preserve interacting semantics.
  case page
}

/// Metadata for one transmitted PDF page.
public struct PDFPageOutput: Sendable, Hashable {
  /// The one-based output ordinal.
  public let ordinal: Int
  /// The active PostScript device at transmission.
  public let device: GraphicsDeviceSnapshot
  /// The eventual indirect page reference, when assigned during finalization.
  public let pageReference: PDFObjectReference?
  /// The page's fallback disposition.
  public let fallback: PDFPageFallbackDisposition

  /// Creates page output metadata.
  public init(
    ordinal: Int,
    device: GraphicsDeviceSnapshot,
    pageReference: PDFObjectReference? = nil,
    fallback: PDFPageFallbackDisposition = .vector
  ) {
    self.ordinal = ordinal
    self.device = device
    self.pageReference = pageReference
    self.fallback = fallback
  }
}
