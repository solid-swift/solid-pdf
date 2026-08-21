/// The language-visible technology used to realize a PostScript font.
public enum GraphicsFontTechnology: Sendable, Hashable {
  /// A composite Type 0 font.
  case composite
  /// An Adobe Type 1 font.
  case type1
  /// A Compact Font Format font.
  case compactFontFormat
  /// A procedure-defined Type 3 font.
  case type3
  /// A Type 42 sfnt font.
  case trueType
  /// A CIDFontType 0 charstring font.
  case cidType0
  /// A CIDFontType 1 procedure font.
  case cidType1
  /// A CIDFontType 2 sfnt font.
  case cidType2
  /// A CIDFontType 4 bitmap font.
  case bitmap
  /// A provider-defined Type 14 Chameleon font.
  case chameleon
  /// A source-compatible producer did not identify its font technology.
  case unknown
}
