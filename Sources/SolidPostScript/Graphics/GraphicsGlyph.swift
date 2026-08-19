import Foundation
import SolidFont

/// A PostScript character or glyph selector preserved for renderer output.
public enum GraphicsGlyphSelector: Sendable, Hashable {
  /// A byte code from a base-font show string.
  case character(UInt8)
  /// A PostScript glyph name.
  case name(String)
  /// A font glyph index.
  case index(UInt32)
  /// A character identifier selected by a CMap.
  case cid(UInt32)
}

/// Horizontal and vertical metrics for a resolved glyph.
public struct GraphicsGlyphMetrics: Sendable, Hashable {
  /// The horizontal advance in glyph space.
  public let horizontalAdvance: GraphicsPoint
  /// The vertical advance in glyph space.
  public let verticalAdvance: GraphicsPoint?
  /// The vertical-origin displacement in glyph space.
  public let verticalOrigin: GraphicsPoint?
  /// The glyph bounds in glyph space.
  public let bounds: GraphicsRect?

  /// Creates glyph metrics.
  public init(
    horizontalAdvance: GraphicsPoint,
    verticalAdvance: GraphicsPoint? = nil,
    verticalOrigin: GraphicsPoint? = nil,
    bounds: GraphicsRect? = nil
  ) {
    self.horizontalAdvance = horizontalAdvance
    self.verticalAdvance = verticalAdvance
    self.verticalOrigin = verticalOrigin
    self.bounds = bounds
  }
}

/// A portable glyph drawing program retained as a backend fallback.
public enum GraphicsGlyphProgram: Sendable, Hashable {
  /// A device-independent outline.
  case outline(GraphicsPath)
  /// A monochrome coverage bitmap.
  case bitmap(FontGlyphBitmap)
  /// A Type 3 display list.
  case displayList(GraphicsDisplayList)
  /// A spacing-only glyph.
  case empty
  /// A missing glyph that paints nothing.
  case missing
}

/// One fully resolved glyph independent of a target backend.
public struct GraphicsGlyphDescription: Sendable, Hashable {
  /// The language-visible selector.
  public let selector: GraphicsGlyphSelector
  /// The resolved metrics.
  public let metrics: GraphicsGlyphMetrics
  /// The portable rendering fallback.
  public let program: GraphicsGlyphProgram

  /// Creates a resolved glyph description.
  public init(
    selector: GraphicsGlyphSelector,
    metrics: GraphicsGlyphMetrics,
    program: GraphicsGlyphProgram
  ) {
    self.selector = selector
    self.metrics = metrics
    self.program = program
  }
}

/// A resolved glyph positioned in device space.
public struct GraphicsGlyphPlacement: Sendable, Hashable {
  /// The resolved glyph.
  public let glyph: GraphicsGlyphDescription
  /// The descendant font that supplied this glyph, or the run's root font for legacy producers.
  public let font: GraphicsFontDescription?
  /// The device-space glyph origin.
  public let origin: GraphicsPoint
  /// The glyph-to-device transform.
  public let transform: GraphicsMatrix
  /// The user-space advance applied after this glyph.
  public let advance: GraphicsPoint

  /// Creates a glyph placement.
  public init(
    glyph: GraphicsGlyphDescription,
    origin: GraphicsPoint,
    transform: GraphicsMatrix,
    advance: GraphicsPoint,
    font: GraphicsFontDescription? = nil
  ) {
    self.glyph = glyph
    self.font = font
    self.origin = origin
    self.transform = transform
    self.advance = advance
  }
}

/// An ordered semantic PostScript glyph run.
public struct GraphicsGlyphRun: Sendable, Hashable {
  /// The root font selected by `setfont`.
  public let rootFont: GraphicsFontDescription
  /// Ordered glyph placements, possibly from descendant fonts.
  public let glyphs: [GraphicsGlyphPlacement]

  /// Creates a glyph run.
  public init(rootFont: GraphicsFontDescription, glyphs: [GraphicsGlyphPlacement]) {
    self.rootFont = rootFont
    self.glyphs = glyphs
  }
}
