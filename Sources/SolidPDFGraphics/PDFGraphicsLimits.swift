/// Resource limits for one PDF graphics interpretation.
public struct PDFGraphicsLimits: Sendable, Hashable {
  /// Maximum operators executed on one page.
  public let maximumOperatorsPerPage: Int
  /// Maximum saved PDF graphics-state entries.
  public let maximumGraphicsStateDepth: Int
  /// Maximum nested resource, form, and pattern scopes.
  public let maximumResourceDepth: Int
  /// Maximum decoded pixels in one image.
  public let maximumImagePixels: Int
  /// Maximum interpretation scratch retained by one render.
  public let maximumScratchBytes: Int
  /// Maximum resolved font resources in one render.
  public let maximumFonts: Int
  /// Maximum decoded bytes in one CMap program.
  public let maximumCMapBytes: Int
  /// Maximum mappings retained by one CMap.
  public let maximumCMapEntries: Int
  /// Maximum glyphs interpreted on one page.
  public let maximumGlyphsPerPage: Int
  /// Maximum nested Type 3 glyph interpretation depth.
  public let maximumType3Depth: Int
  /// Maximum decoded portable font-program bytes retained by one render.
  public let maximumDecodedFontBytes: Int
  /// Maximum nested marked-content scopes.
  public let maximumMarkedContentDepth: Int
  /// Maximum semantic entries retained from one property list.
  public let maximumMarkedContentProperties: Int

  /// Creates interpretation limits.
  public init(
    maximumOperatorsPerPage: Int = 10_000_000,
    maximumGraphicsStateDepth: Int = 256,
    maximumResourceDepth: Int = 64,
    maximumImagePixels: Int = 128_000_000,
    maximumScratchBytes: Int = 512 * 1_024 * 1_024,
    maximumFonts: Int = 4_096,
    maximumCMapBytes: Int = 64 * 1_024 * 1_024,
    maximumCMapEntries: Int = 1_000_000,
    maximumGlyphsPerPage: Int = 10_000_000,
    maximumType3Depth: Int = 32,
    maximumDecodedFontBytes: Int = 256 * 1_024 * 1_024,
    maximumMarkedContentDepth: Int = 256,
    maximumMarkedContentProperties: Int = 4_096
  ) {
    self.maximumOperatorsPerPage = maximumOperatorsPerPage
    self.maximumGraphicsStateDepth = maximumGraphicsStateDepth
    self.maximumResourceDepth = maximumResourceDepth
    self.maximumImagePixels = maximumImagePixels
    self.maximumScratchBytes = maximumScratchBytes
    self.maximumFonts = maximumFonts
    self.maximumCMapBytes = maximumCMapBytes
    self.maximumCMapEntries = maximumCMapEntries
    self.maximumGlyphsPerPage = maximumGlyphsPerPage
    self.maximumType3Depth = maximumType3Depth
    self.maximumDecodedFontBytes = maximumDecodedFontBytes
    self.maximumMarkedContentDepth = maximumMarkedContentDepth
    self.maximumMarkedContentProperties = maximumMarkedContentProperties
  }
}
