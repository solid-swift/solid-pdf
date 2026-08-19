#if os(Linux)
import CFontconfig
import CFreeType
import Foundation
import SolidFont
import SolidPostScript

/// Discovers Fontconfig faces and resolves their glyphs through FreeType.
public struct FreeTypeFontProvider: FontResourceProvider, Sendable {
  /// A stable provider identifier used by PostScript font IDs.
  public let identifier = "org.solidpdf.freetype"

  /// Creates a FreeType and Fontconfig font provider.
  public init() {}

  /// Returns installed PostScript font names known to Fontconfig.
  public func availableFontNames() async throws -> [String] {
    let count = solid_fc_postscript_names(nil, 0)
    guard count > 0 else { return [] }
    var bytes = [CChar](repeating: 0, count: count)
    let written = solid_fc_postscript_names(&bytes, bytes.count)
    guard written == count else { return [] }
    var names: [String] = []
    var start = 0
    for index in bytes.indices where bytes[index] == 0 {
      if index > start { names.append(Self.string(from: Array(bytes[start..<index]))) }
      start = index + 1
    }
    return Array(Set(names)).sorted()
  }

  /// Resolves a PostScript font name through Fontconfig and copies its data into a portable asset.
  public func resolve(_ query: FontResourceQuery) async throws -> FontProviderFace? {
    guard let match = Self.match(query.name) else { return nil }
    let data = try Data(contentsOf: URL(fileURLWithPath: match.path), options: .mappedIfSafe)
    let result: FontProviderFace?? = try data.withUnsafeBytes { bytes in
      try Self.withFace(data: bytes, index: match.index) { face -> FontProviderFace? in
        let resolvedName = FT_Get_Postscript_Name(face).map { String(cString: $0) }
          ?? match.resolvedName ?? query.name
        guard query.permitsSubstitution || resolvedName == query.name else { return nil }
        let descriptor = try FontDescriptor(
          postScriptName: resolvedName,
          familyName: face.pointee.family_name.map { String(cString: $0) },
          styleName: face.pointee.style_name.map { String(cString: $0) },
          unitsPerEm: UInt32(max(1, Int(face.pointee.units_per_EM)))
        )
        let formatName = FT_Get_Font_Format(face).map { String(cString: $0) }
        let format: FontAsset.Format = switch formatName {
        case "Type 1": .type1
        case "CFF": .compactFontFormat
        default: .sfnt
        }
        let asset = try FontAsset(
          descriptor: descriptor,
          format: format,
          data: data,
          faceIndex: match.index
        )
        return FontProviderFace(
          providerIdentifier: identifier,
          faceKey: "\(match.path)#\(match.index)",
          asset: asset,
          isSubstitute: resolvedName != query.name
        )
      }
    }
    return result ?? nil
  }

  /// Resolves an exact glyph selector without Unicode shaping or fallback.
  public func glyph(_ selector: FontGlyphSelector, in face: FontProviderFace) async throws -> FontGlyph? {
    guard face.providerIdentifier == identifier, let data = face.asset.data else { return nil }
    let result: FontGlyph?? = try data.withUnsafeBytes { bytes in
      try Self.withFace(data: bytes, index: face.asset.faceIndex) { ftFace -> FontGlyph? in
        guard let glyphIndex = Self.glyphIndex(selector, in: ftFace),
          FT_Load_Glyph(
            ftFace,
            glyphIndex,
            FT_Int32(FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP)
          ) == 0,
          let slot = ftFace.pointee.glyph
        else { return nil }
        return FontGlyph(
          selector: selector,
          metrics: Self.metrics(slot: slot),
          program: Self.program(slot: slot)
        )
      }
    }
    return result ?? nil
  }
}

private extension FreeTypeFontProvider {
  struct Match {
    let path: String
    let index: Int
    let resolvedName: String?
  }

  static func match(_ name: String) -> Match? {
    var path = [CChar](repeating: 0, count: 4_096)
    var resolved = [CChar](repeating: 0, count: 512)
    var index: Int32 = 0
    let matched = name.withCString { namePointer in
      solid_fc_match_font(namePointer, &path, path.count, &index, &resolved, resolved.count)
    }
    guard matched != 0 else { return nil }
    return Match(
      path: string(from: path),
      index: Int(index),
      resolvedName: resolved[0] == 0 ? nil : string(from: resolved)
    )
  }

  static func string(from buffer: [CChar]) -> String {
    String(
      decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
      as: UTF8.self
    )
  }

  static func withFace<Result>(
    data: UnsafeRawBufferPointer,
    index: Int,
    _ body: (FT_Face) throws -> Result
  ) throws -> Result? {
    guard let base = data.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
    var library: FT_Library?
    guard FT_Init_FreeType(&library) == 0, let library else { return nil }
    defer { FT_Done_FreeType(library) }
    var face: FT_Face?
    guard FT_New_Memory_Face(library, base, data.count, index, &face) == 0, let face else { return nil }
    defer { FT_Done_Face(face) }
    return try body(face)
  }

  static func glyphIndex(_ selector: FontGlyphSelector, in face: FT_Face) -> FT_UInt? {
    switch selector {
    case .name(let name):
      let result = name.withCString { FT_Get_Name_Index(face, $0) }
      return result == 0 && name != ".notdef" ? nil : result
    case .index(let index), .cid(let index):
      return FT_UInt(index)
    }
  }

  static func metrics(slot: FT_GlyphSlot) -> FontGlyphMetrics {
    let values = slot.pointee.metrics
    return FontGlyphMetrics(
      horizontalAdvance: FontPoint(x: Double(values.horiAdvance), y: 0),
      verticalAdvance: FontPoint(x: 0, y: Double(-values.vertAdvance)),
      verticalOrigin: FontPoint(x: Double(values.vertBearingX), y: Double(values.vertBearingY)),
      bounds: FontBounds(
        minimumX: Double(values.horiBearingX),
        minimumY: Double(values.horiBearingY - values.height),
        maximumX: Double(values.horiBearingX + values.width),
        maximumY: Double(values.horiBearingY)
      )
    )
  }

  static func program(slot: FT_GlyphSlot) -> FontGlyphProgram {
    guard slot.pointee.format == FT_GLYPH_FORMAT_OUTLINE else { return .empty }
    var outline = slot.pointee.outline
    let count = solid_ft_outline_events(&outline, nil, 0)
    guard count > 0 else { return .empty }
    var events = [SolidFTOutlineEvent](repeating: SolidFTOutlineEvent(), count: count)
    let written = events.withUnsafeMutableBufferPointer { buffer in
      solid_ft_outline_events(&outline, buffer.baseAddress, buffer.count)
    }
    guard written == count else { return .empty }
    var elements: [FontOutline.Element] = []
    elements.reserveCapacity(events.count + Int(outline.n_contours))
    var hasContour = false
    for event in events {
      switch event.kind {
      case 0:
        if hasContour { elements.append(.close) }
        elements.append(.move(FontPoint(x: Double(event.x1), y: Double(event.y1))))
        hasContour = true
      case 1:
        elements.append(.line(FontPoint(x: Double(event.x1), y: Double(event.y1))))
      case 2:
        elements.append(.quadratic(
          control: FontPoint(x: Double(event.x1), y: Double(event.y1)),
          end: FontPoint(x: Double(event.x2), y: Double(event.y2))
        ))
      case 3:
        elements.append(.cubic(
          control1: FontPoint(x: Double(event.x1), y: Double(event.y1)),
          control2: FontPoint(x: Double(event.x2), y: Double(event.y2)),
          end: FontPoint(x: Double(event.x3), y: Double(event.y3))
        ))
      default:
        return .empty
      }
    }
    if hasContour { elements.append(.close) }
    return .outline(FontOutline(elements: elements))
  }
}
#endif
