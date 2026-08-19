import Foundation

/// A backend-independent glyph selector.
public enum FontGlyphSelector: Sendable, Hashable {
  /// Selects a glyph by PostScript glyph name.
  case name(String)
  /// Selects a glyph by font glyph index.
  case index(UInt32)
  /// Selects a glyph by character identifier.
  case cid(UInt32)
}

/// Horizontal and vertical metrics for one glyph.
public struct FontGlyphMetrics: Sendable, Hashable {
  /// The horizontal advance vector.
  public let horizontalAdvance: FontPoint
  /// The vertical advance vector.
  public let verticalAdvance: FontPoint?
  /// The vertical-origin displacement.
  public let verticalOrigin: FontPoint?
  /// The glyph bounds in design coordinates.
  public let bounds: FontBounds?

  /// Creates glyph metrics.
  public init(
    horizontalAdvance: FontPoint,
    verticalAdvance: FontPoint? = nil,
    verticalOrigin: FontPoint? = nil,
    bounds: FontBounds? = nil
  ) {
    self.horizontalAdvance = horizontalAdvance
    self.verticalAdvance = verticalAdvance
    self.verticalOrigin = verticalOrigin
    self.bounds = bounds
  }
}

/// A portable monochrome glyph bitmap.
public struct FontGlyphBitmap: Sendable, Hashable {
  /// The bitmap width in pixels.
  public let width: Int
  /// The bitmap height in pixels.
  public let height: Int
  /// The byte distance between rows.
  public let bytesPerRow: Int
  /// The horizontal offset from the glyph origin.
  public let originX: Int
  /// The vertical offset from the glyph origin.
  public let originY: Int
  /// Row-major 8-bit coverage data.
  public let coverage: Data

  /// Creates a glyph bitmap.
  public init(
    width: Int,
    height: Int,
    bytesPerRow: Int,
    originX: Int,
    originY: Int,
    coverage: Data
  ) throws {
    guard width >= 0, height >= 0, bytesPerRow >= width,
      height == 0 || bytesPerRow <= Int.max / height,
      coverage.count == bytesPerRow * height
    else { throw FontError.invalidData }
    self.width = width
    self.height = height
    self.bytesPerRow = bytesPerRow
    self.originX = originX
    self.originY = originY
    self.coverage = coverage
  }
}

/// A decoded portable glyph program.
public enum FontGlyphProgram: Sendable, Hashable {
  /// A scalable outline.
  case outline(FontOutline)
  /// A monochrome coverage bitmap.
  case bitmap(FontGlyphBitmap)
  /// A spacing-only glyph.
  case empty
}

/// A complete portable glyph result.
public struct FontGlyph: Sendable, Hashable {
  /// The resolved selector.
  public let selector: FontGlyphSelector
  /// The glyph metrics.
  public let metrics: FontGlyphMetrics
  /// The glyph drawing program.
  public let program: FontGlyphProgram

  /// Creates a portable glyph.
  public init(selector: FontGlyphSelector, metrics: FontGlyphMetrics, program: FontGlyphProgram) {
    self.selector = selector
    self.metrics = metrics
    self.program = program
  }
}
