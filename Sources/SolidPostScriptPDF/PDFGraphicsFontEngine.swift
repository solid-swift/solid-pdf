import SolidPostScript

/// The render-scoped font engine used by the PDF graphics target.
public struct PDFGraphicsFontEngine: GraphicsFontEngine, Sendable {
  /// Creates a PDF font engine.
  public init() {}

  /// Creates one isolated PDF font session.
  public func makeSession(for device: GraphicsDeviceDescriptor) -> sending PDFGraphicsFontSession {
    PDFGraphicsFontSession()
  }
}

/// A PDF font session retaining portable font and glyph descriptions.
public final class PDFGraphicsFontSession: GraphicsFontSession {
  /// Creates a PDF font session.
  public init() {}

  /// Returns the portable font description used for PDF resource selection.
  public func prepare(_ font: GraphicsFontDescription) -> GraphicsFontDescription? { font }

  /// Returns the portable glyph program used for embedding or Type 3 fallback.
  public func prepare(
    _ glyph: GraphicsGlyphDescription,
    in font: borrowing GraphicsFontDescription
  ) -> GraphicsGlyphDescription? {
    glyph
  }
}
