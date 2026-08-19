#if canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation
import SolidPostScript

/// A glyph prepared for an optional CoreText renderer fast path.
public struct CoreTextPreparedGlyph {
  /// The exact glyph selected by the PostScript interpreter.
  public let glyph: CGGlyph
  /// The portable description retained for non-equivalent rendering paths.
  public let fallback: GraphicsGlyphDescription
}

/// Creates renderer-owned CoreText font preparation sessions.
public struct CoreTextGraphicsFontEngine: GraphicsFontEngine, Sendable {
  /// Creates a CoreText graphics font engine.
  public init() {}

  /// Creates an isolated CoreText preparation session.
  public func makeSession(for device: GraphicsDeviceDescriptor) -> sending CoreTextGraphicsFontSession {
    CoreTextGraphicsFontSession()
  }
}

/// Prepares exact glyph indexes without performing Unicode shaping or fallback.
public final class CoreTextGraphicsFontSession: GraphicsFontSession {
  /// Creates a CoreText font session.
  public init() {}

  /// Creates a data-backed CoreText face for a portable font asset.
  public func prepare(_ font: GraphicsFontDescription) throws -> CTFont? {
    guard let asset = font.asset, let data = asset.data else { return nil }
    let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor] ?? []
    guard descriptors.indices.contains(asset.faceIndex) else { return nil }
    let descriptor = descriptors[asset.faceIndex]
    return CTFontCreateWithFontDescriptor(descriptor, CGFloat(asset.descriptor.unitsPerEm), nil)
  }

  /// Prepares the interpreter-selected glyph without applying backend character mapping.
  public func prepare(
    _ glyph: GraphicsGlyphDescription,
    in font: borrowing CTFont
  ) throws -> CoreTextPreparedGlyph? {
    let index: UInt32
    switch glyph.selector {
    case .index(let value), .cid(let value):
      index = value
    case .name(let name):
      index = UInt32(CTFontGetGlyphWithName(font, name as CFString))
    case .character:
      return nil
    }
    guard index <= UInt32(CGGlyph.max) else { return nil }
    return CoreTextPreparedGlyph(glyph: CGGlyph(index), fallback: glyph)
  }
}
#endif
