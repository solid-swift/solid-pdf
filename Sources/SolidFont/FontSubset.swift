import Foundation

/// A deterministic, validated font program containing selected glyphs.
public struct FontSubset: Sendable, Hashable {
  /// Face-wide metrics used when constructing document font descriptors.
  public struct Metrics: Sendable, Hashable {
    /// The typographic ascender in design units.
    public let ascent: Double
    /// The typographic descender in design units.
    public let descent: Double
    /// The cap height in design units, when known.
    public let capHeight: Double?
    /// The italic angle in counter-clockwise degrees.
    public let italicAngle: Double
    /// A representative vertical stem width in design units.
    public let stemV: Double?
    /// Bounds encompassing the retained face.
    public let bounds: FontBounds?

    /// Creates face-wide font metrics.
    public init(
      ascent: Double = 0,
      descent: Double = 0,
      capHeight: Double? = nil,
      italicAngle: Double = 0,
      stemV: Double? = nil,
      bounds: FontBounds? = nil
    ) {
      self.ascent = ascent
      self.descent = descent
      self.capHeight = capHeight
      self.italicAngle = italicAngle
      self.stemV = stemV
      self.bounds = bounds
    }
  }

  /// The complete deterministic embedded program.
  public let data: Data
  /// The program representation.
  public let format: FontEmbeddedProgramFormat
  /// The subset PostScript name, including its six-letter prefix.
  public let postScriptName: String
  /// Design-space units per em.
  public let unitsPerEm: UInt32
  /// Face-wide metrics.
  public let metrics: Metrics
  /// Retained glyphs in subset-index order.
  public let glyphs: [FontSubsetGlyph]
  /// Original-to-subset glyph mapping.
  public let glyphMapping: [UInt32: UInt32]
  /// Type 1 clear-text, encrypted, and trailer segment lengths.
  public let type1SegmentLengths: [Int]?

  /// Creates a validated subset result.
  public init(
    data: Data,
    format: FontEmbeddedProgramFormat,
    postScriptName: String,
    unitsPerEm: UInt32,
    metrics: Metrics = .init(),
    glyphs: [FontSubsetGlyph],
    type1SegmentLengths: [Int]? = nil
  ) throws {
    guard !data.isEmpty, !postScriptName.isEmpty, unitsPerEm > 0,
      Set(glyphs.map(\.originalIndex)).count == glyphs.count,
      Set(glyphs.map(\.subsetIndex)).count == glyphs.count
    else { throw FontError.invalidData }
    self.data = data
    self.format = format
    self.postScriptName = postScriptName
    self.unitsPerEm = unitsPerEm
    self.metrics = metrics
    self.glyphs = glyphs.sorted { $0.subsetIndex < $1.subsetIndex }
    self.glyphMapping = Dictionary(uniqueKeysWithValues: glyphs.map { ($0.originalIndex, $0.subsetIndex) })
    self.type1SegmentLengths = type1SegmentLengths
  }
}
