import Foundation

/// A variation-axis value selected for a font face.
public struct FontVariationCoordinate: Sendable, Hashable {
  /// The four-character OpenType axis tag.
  public let tag: UInt32
  /// The selected axis value.
  public let value: Double

  /// Creates a variation coordinate.
  public init(tag: UInt32, value: Double) {
    self.tag = tag
    self.value = value
  }
}

/// Portable descriptive metadata for one font face.
public struct FontDescriptor: Sendable, Hashable {
  /// The PostScript name when available.
  public let postScriptName: String
  /// The display family name when available.
  public let familyName: String?
  /// The display style name when available.
  public let styleName: String?
  /// The design-space units per em.
  public let unitsPerEm: UInt32
  /// Selected variation coordinates.
  public let variations: [FontVariationCoordinate]
  /// Whether glyph outlines may be exposed through language-level path inspection.
  public let outlineAccess: FontOutlineAccess

  /// Creates a font descriptor.
  public init(
    postScriptName: String,
    familyName: String? = nil,
    styleName: String? = nil,
    unitsPerEm: UInt32 = 1_000,
    variations: [FontVariationCoordinate] = [],
    outlineAccess: FontOutlineAccess = .extractable
  ) throws {
    guard !postScriptName.isEmpty, unitsPerEm > 0 else { throw FontError.invalidData }
    self.postScriptName = postScriptName
    self.familyName = familyName
    self.styleName = styleName
    self.unitsPerEm = unitsPerEm
    self.variations = variations
    self.outlineAccess = outlineAccess
  }
}
