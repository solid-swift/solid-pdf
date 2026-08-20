import Foundation

/// The embedding restrictions declared by a portable font asset.
public struct FontEmbeddingPermissions: Sendable, Hashable {
  /// Whether a document may embed the font program.
  public let allowsEmbedding: Bool
  /// Whether an embedded font may contain fewer than all glyphs.
  public let allowsSubsetting: Bool
  /// Whether embedding is restricted to bitmap representations.
  public let bitmapOnly: Bool

  /// Creates an embedding-permission description.
  public init(allowsEmbedding: Bool, allowsSubsetting: Bool, bitmapOnly: Bool) {
    self.allowsEmbedding = allowsEmbedding
    self.allowsSubsetting = allowsSubsetting
    self.bitmapOnly = bitmapOnly
  }

  /// Unrestricted installable embedding.
  public static let installable = Self(allowsEmbedding: true, allowsSubsetting: true, bitmapOnly: false)
}

/// A deterministic font-embedding decision and its immutable font bytes.
public struct FontEmbeddingPlan: Sendable, Hashable {
  /// How the asset must be represented in a document.
  public enum Strategy: Sendable, Hashable {
    /// Embed a rebuilt font program containing the selected glyph closure.
    case subsetFont
    /// Embed the complete original font program.
    case completeFont
    /// Build a document-native font from portable glyph programs.
    case portableGlyphs
  }

  /// The selected strategy.
  public let strategy: Strategy
  /// The original font bytes when complete embedding is selected.
  public let data: Data?
  /// A stable six-letter PDF subset prefix.
  public let subsetPrefix: String
  /// Glyph identifiers included by the caller.
  public let glyphs: [UInt32]
  /// The rebuilt subset when `strategy` is `subsetFont`.
  public let subset: FontSubset?

  /// Creates a font embedding plan.
  public init(
    strategy: Strategy,
    data: Data?,
    subsetPrefix: String,
    glyphs: [UInt32],
    subset: FontSubset? = nil
  ) {
    self.strategy = strategy
    self.data = data
    self.subsetPrefix = subsetPrefix
    self.glyphs = glyphs
    self.subset = subset
  }
}

/// Examines portable font assets and produces deterministic embedding plans.
public enum FontSubsetter {
  /// Returns the embedding restrictions declared by `asset`.
  public static func permissions(for asset: FontAsset) throws -> FontEmbeddingPermissions {
    guard asset.format == .sfnt, let data = asset.data else { return .installable }
    let collection = try SFNTCollection(data: data)
    guard asset.faceIndex < collection.faces.count else { throw FontError.range }
    let os2Tag: UInt32 = 0x4F53_2F32
    guard let os2 = try collection.faces[asset.faceIndex].data(for: os2Tag, in: data), os2.count >= 10 else {
      return .installable
    }
    let fsType = UInt16(os2[8]) << 8 | UInt16(os2[9])
    return FontEmbeddingPermissions(
      allowsEmbedding: fsType & 0x0002 == 0,
      allowsSubsetting: fsType & 0x0100 == 0,
      bitmapOnly: fsType & 0x0200 != 0
    )
  }

  /// Plans embedding for the requested glyph identifiers.
  ///
  /// The portable PDF layer currently embeds a permitted binary asset whole and
  /// uses document-native glyph programs when rights prohibit that representation.
  public static func plan(asset: FontAsset, glyphs: some Sequence<UInt32>) throws -> FontEmbeddingPlan {
    let glyphs = Array(Set(glyphs)).sorted()
    let permissions = try permissions(for: asset)
    let prefix = subsetPrefix(asset: asset, glyphs: glyphs)
    guard permissions.allowsEmbedding, !permissions.bitmapOnly, let data = asset.data else {
      return FontEmbeddingPlan(strategy: .portableGlyphs, data: nil, subsetPrefix: prefix, glyphs: glyphs)
    }
    if permissions.allowsSubsetting,
      let subset = try? subset(asset, request: FontSubsetRequest(glyphIndexes: glyphs))
    {
      return FontEmbeddingPlan(
        strategy: .subsetFont,
        data: subset.data,
        subsetPrefix: prefix,
        glyphs: glyphs,
        subset: subset
      )
    }
    return FontEmbeddingPlan(strategy: .completeFont, data: data, subsetPrefix: prefix, glyphs: glyphs)
  }

  /// Rebuilds one font asset with only the requested glyph closure.
  public static func subset(
    _ asset: FontAsset,
    request: FontSubsetRequest,
    limits: FontParsingLimits = .default
  ) throws -> FontSubset {
    guard let data = asset.data else { throw FontError.invalidData }
    guard data.count <= limits.maximumDataBytes else { throw FontError.limitExceeded }
    let prefix = subsetPrefix(asset: asset, glyphs: request.glyphIndexes)
    switch asset.format {
    case .compactFontFormat:
      return try CFFFontSubsetter.subset(
        data: data,
        faceIndex: asset.faceIndex,
        descriptor: asset.descriptor,
        request: request,
        prefix: prefix,
        limits: limits
      )
    case .sfnt:
      let permissions = try permissions(for: asset)
      guard permissions.allowsEmbedding, !permissions.bitmapOnly else {
        throw FontError.unsupportedFormat
      }
      return try SFNTFontSubsetter.subset(
        data: data,
        faceIndex: asset.faceIndex,
        descriptor: asset.descriptor,
        request: request,
        forcesCompleteFace: !permissions.allowsSubsetting,
        prefix: prefix,
        limits: limits
      )
    case .type1:
      return try Type1FontSubsetter.subset(
        data: data,
        descriptor: asset.descriptor,
        request: request,
        prefix: prefix,
        limits: limits
      )
    case .type3, .chameleon:
      throw FontError.unsupportedFormat
    }
  }

  private static func subsetPrefix(asset: FontAsset, glyphs: [UInt32]) -> String {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    func absorb(_ byte: UInt8) {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01B3
    }
    for byte in asset.data ?? Data(asset.descriptor.postScriptName.utf8) { absorb(byte) }
    for glyph in glyphs {
      absorb(UInt8(truncatingIfNeeded: glyph >> 24))
      absorb(UInt8(truncatingIfNeeded: glyph >> 16))
      absorb(UInt8(truncatingIfNeeded: glyph >> 8))
      absorb(UInt8(truncatingIfNeeded: glyph))
    }
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
    return String(decoding: (0..<6).map { index in
      alphabet[Int((hash >> UInt64(index * 8)) & 0xFF) % alphabet.count]
    }, as: UTF8.self)
  }
}
