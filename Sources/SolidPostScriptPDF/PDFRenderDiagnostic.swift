/// A diagnostic explaining a PDF rendering decision.
public struct PDFRenderDiagnostic: Sendable, Hashable {
  /// A stable diagnostic category.
  public enum Kind: Sendable, Hashable {
    /// A glyph used a portable outline or Type 3 representation.
    case fontFallback
    /// One self-contained effect was rasterized.
    case localizedRasterization
    /// A complete page was rasterized to preserve interacting semantics.
    case pageRasterization
    /// Output was adjusted for PDF 1.7 compatibility.
    case compatibilityDowngrade
    /// Metadata could not be represented.
    case discardedMetadata
  }

  /// The diagnostic category.
  public let kind: Kind
  /// The one-based output page, when applicable.
  public let page: Int?
  /// A human-readable explanation.
  public let message: String

  /// Creates a rendering diagnostic.
  public init(kind: Kind, page: Int? = nil, message: String) {
    self.kind = kind
    self.page = page
    self.message = message
  }
}
