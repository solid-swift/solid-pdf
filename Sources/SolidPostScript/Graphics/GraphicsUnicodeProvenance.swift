/// The authority that established Unicode extraction metadata for a glyph.
public enum GraphicsUnicodeProvenance: Sendable, Hashable {
  /// A PostScript base-font Encoding and its glyph name established the mapping.
  case postScriptEncoding
  /// A PostScript CMap established the mapping.
  case postScriptCMap
  /// An embedded font character map established the mapping.
  case fontCharacterMap
  /// Adobe glyph-name rules established the mapping.
  case glyphName
  /// A configured font provider supplied the mapping.
  case provider
  /// A PDF simple-font Encoding and glyph name established the mapping.
  case pdfEncoding
  /// A PDF composite-font CMap or standard collection mapping established the mapping.
  case pdfCMap
  /// A PDF `/ToUnicode` CMap explicitly established the mapping.
  case pdfToUnicode
}
