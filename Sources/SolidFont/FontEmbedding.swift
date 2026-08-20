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

  /// Creates a font embedding plan.
  public init(strategy: Strategy, data: Data?, subsetPrefix: String, glyphs: [UInt32]) {
    self.strategy = strategy
    self.data = data
    self.subsetPrefix = subsetPrefix
    self.glyphs = glyphs
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
    return FontEmbeddingPlan(strategy: .completeFont, data: data, subsetPrefix: prefix, glyphs: glyphs)
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
