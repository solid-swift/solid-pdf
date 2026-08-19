#if canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation
import SolidFont
import SolidPostScript

/// Discovers installed Apple fonts and exposes their glyphs as portable font programs.
public struct CoreTextFontProvider: FontResourceProvider, Sendable {
  /// A stable provider identifier used by PostScript font IDs.
  public let identifier = "org.solidpdf.coretext"

  /// Creates a CoreText font provider.
  public init() {}

  /// Returns the installed PostScript font names known to CoreText.
  public func availableFontNames() async throws -> [String] {
    (CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).sorted()
  }

  /// Resolves an installed font and materializes its data without registering it process-wide.
  public func resolve(_ query: FontResourceQuery) async throws -> FontProviderFace? {
    let font = CTFontCreateWithName(query.name as CFString, 1_000, nil)
    let resolvedName = CTFontCopyPostScriptName(font) as String
    guard query.permitsSubstitution || resolvedName == query.name else { return nil }
    guard let asset = try Self.asset(for: font) else { return nil }
    return FontProviderFace(
      providerIdentifier: identifier,
      faceKey: resolvedName,
      asset: asset,
      isSubstitute: resolvedName != query.name
    )
  }

  /// Resolves a selected glyph using CoreText's glyph-index and outline APIs.
  public func glyph(_ selector: FontGlyphSelector, in face: FontProviderFace) async throws -> FontGlyph? {
    guard face.providerIdentifier == identifier,
      let font = Self.font(for: face.asset),
      let glyph = Self.glyphIndex(selector, in: font)
    else { return nil }
    return Self.portableGlyph(selector: selector, glyph: glyph, font: font)
  }
}

private extension CoreTextFontProvider {
  static func asset(for font: CTFont) throws -> FontAsset? {
    let descriptor = CTFontCopyFontDescriptor(font)
    guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else {
      return nil
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let metadata = try FontDescriptor(
      postScriptName: CTFontCopyPostScriptName(font) as String,
      familyName: CTFontCopyFamilyName(font) as String,
      styleName: CTFontCopyName(font, kCTFontStyleNameKey) as String?,
      unitsPerEm: UInt32(CTFontGetUnitsPerEm(font))
    )
    return try FontAsset(descriptor: metadata, format: .sfnt, data: data)
  }

  static func font(for asset: FontAsset) -> CTFont? {
    guard let data = asset.data,
      let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData)
    else { return nil }
    return CTFontCreateWithFontDescriptor(descriptor, CGFloat(asset.descriptor.unitsPerEm), nil)
  }

  static func glyphIndex(_ selector: FontGlyphSelector, in font: CTFont) -> CGGlyph? {
    let glyph: CGGlyph
    switch selector {
    case .name(let name):
      glyph = CTFontGetGlyphWithName(font, name as CFString)
    case .index(let index), .cid(let index):
      guard index <= UInt32(CGGlyph.max) else { return nil }
      glyph = CGGlyph(index)
    }
    return glyph
  }

  static func portableGlyph(selector: FontGlyphSelector, glyph: CGGlyph, font: CTFont) -> FontGlyph {
    var glyph = glyph
    var advance = CGSize.zero
    var bounds = CGRect.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
    CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
    var verticalTranslation = CGSize.zero
    CTFontGetVerticalTranslationsForGlyphs(font, &glyph, &verticalTranslation, 1)
    let metrics = FontGlyphMetrics(
      horizontalAdvance: FontPoint(x: advance.width, y: advance.height),
      verticalAdvance: FontPoint(x: 0, y: -CGFloat(CTFontGetUnitsPerEm(font))),
      verticalOrigin: FontPoint(x: verticalTranslation.width, y: verticalTranslation.height),
      bounds: FontBounds(
        minimumX: bounds.minX,
        minimumY: bounds.minY,
        maximumX: bounds.maxX,
        maximumY: bounds.maxY
      )
    )
    let program: FontGlyphProgram
    if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
      program = .outline(FontOutline(elements: path.fontElements))
    } else {
      program = .empty
    }
    return FontGlyph(selector: selector, metrics: metrics, program: program)
  }
}

private extension CGPath {
  var fontElements: [FontOutline.Element] {
    var result: [FontOutline.Element] = []
    applyWithBlock { elementPointer in
      let element = elementPointer.pointee
      switch element.type {
      case .moveToPoint:
        result.append(.move(element.points[0].fontPoint))
      case .addLineToPoint:
        result.append(.line(element.points[0].fontPoint))
      case .addQuadCurveToPoint:
        result.append(.quadratic(control: element.points[0].fontPoint, end: element.points[1].fontPoint))
      case .addCurveToPoint:
        result.append(.cubic(
          control1: element.points[0].fontPoint,
          control2: element.points[1].fontPoint,
          end: element.points[2].fontPoint
        ))
      case .closeSubpath:
        result.append(.close)
      @unknown default:
        break
      }
    }
    return result
  }
}

private extension CGPoint {
  var fontPoint: FontPoint { FontPoint(x: x, y: y) }
}
#endif
