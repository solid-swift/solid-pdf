/// Controls whether a font's outlines may be exposed through PostScript path-inspection operators.
public enum FontOutlineAccess: Sendable, Hashable {
  /// Glyph outlines may be converted into ordinary PostScript paths.
  case extractable
  /// Glyphs may be painted, but their outlines may not be enumerated or exported.
  case protected
}
