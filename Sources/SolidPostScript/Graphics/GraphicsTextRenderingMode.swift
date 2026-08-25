/// The PDF text rendering mode captured by a semantic glyph run.
public enum GraphicsTextRenderingMode: Int, Sendable, Hashable {
  /// Fill glyph interiors.
  case fill = 0
  /// Stroke glyph outlines.
  case stroke = 1
  /// Fill and then stroke glyph outlines.
  case fillStroke = 2
  /// Preserve extraction metadata without painting glyphs.
  case invisible = 3
  /// Fill glyph interiors and add their outlines to the pending text clip.
  case fillClip = 4
  /// Stroke glyph outlines and add them to the pending text clip.
  case strokeClip = 5
  /// Fill and stroke glyph outlines and add them to the pending text clip.
  case fillStrokeClip = 6
  /// Add glyph outlines to the pending text clip without painting them.
  case clip = 7

  /// Whether the mode paints glyph interiors.
  public var fills: Bool {
    switch self {
    case .fill, .fillStroke, .fillClip, .fillStrokeClip: true
    case .stroke, .invisible, .strokeClip, .clip: false
    }
  }

  /// Whether the mode strokes glyph outlines.
  public var strokes: Bool {
    switch self {
    case .stroke, .fillStroke, .strokeClip, .fillStrokeClip: true
    case .fill, .invisible, .fillClip, .clip: false
    }
  }

  /// Whether the mode adds glyph outlines to the text clipping path.
  public var clips: Bool { rawValue >= Self.fillClip.rawValue }
}
