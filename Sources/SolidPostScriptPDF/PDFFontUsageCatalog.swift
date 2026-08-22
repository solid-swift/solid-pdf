import Foundation
import SolidFont
import SolidPDF
import SolidPostScript

struct PDFFontGroupKey: Hashable {
  let asset: FontAsset?
  let fallbackIdentifier: GraphicsFontIdentifier?
  let writingMode: Int

  init(font: GraphicsFontDescription) {
    self.asset = font.asset
    self.fallbackIdentifier = font.asset == nil ? font.identifier : nil
    self.writingMode = font.writingMode
  }
}

struct PDFFontGlyphKey: Hashable {
  let resolvedIndex: UInt32?
  let glyph: GraphicsGlyphDescription?

  init(_ glyph: GraphicsGlyphDescription) {
    self.resolvedIndex = glyph.resolvedGlyphIndex
    self.glyph = glyph.resolvedGlyphIndex == nil ? glyph : nil
  }
}

struct PDFFontGlyphUse {
  let glyph: GraphicsGlyphDescription
  let unicode: [UInt32]?
}

struct PDFFontUsageGroup {
  let font: GraphicsFontDescription
  var glyphs: [PDFFontGlyphKey] = []
  var uses: [PDFFontGlyphKey: PDFFontGlyphUse] = [:]
}

struct PDFFontUsageCatalog {
  private(set) var order: [PDFFontGroupKey] = []
  private(set) var groups: [PDFFontGroupKey: PDFFontUsageGroup] = [:]

  init(plans: [PDFPagePlan]) throws {
    for plan in plans { try collect(plan.effects, depth: 0) }
  }

  private mutating func collect(_ effects: [GraphicsEffect], depth: Int) throws {
    guard depth < 16 else { throw PDFError.limitExceeded }
    for effect in effects {
      try collectPaint(from: effect, depth: depth)
      switch effect {
      case .form(let form, _):
        try collect(form.displayList.effects, depth: depth + 1)
      case .transparencyGroup(let group, _):
        try collect(group.displayList.effects, depth: depth + 1)
      case .text(let run, _):
        for placement in run.glyphs {
          let font = placement.font ?? run.rootFont
          let groupKey = PDFFontGroupKey(font: font)
          if groups[groupKey] == nil {
            order.append(groupKey)
            groups[groupKey] = PDFFontUsageGroup(font: font)
          }
          let glyphKey = PDFFontGlyphKey(placement.glyph)
          if groups[groupKey]!.uses[glyphKey] == nil {
            groups[groupKey]!.glyphs.append(glyphKey)
            groups[groupKey]!.uses[glyphKey] = PDFFontGlyphUse(
              glyph: placement.glyph,
              unicode: unicode(for: placement, font: font)
            )
          }
          if case .displayList(let list) = placement.glyph.program {
            try collect(list.effects, depth: depth + 1)
          }
        }
      default:
        break
      }
    }
  }

  private mutating func collectPaint(from effect: GraphicsEffect, depth: Int) throws {
    let state: GraphicsStateSnapshot =
      switch effect {
      case .fill(_, _, let state), .stroke(_, let state), .userPathFill(_, _, let state),
        .userPathStroke(_, let state), .erase(let state), .fillRectangles(_, let state),
        .strokeRectangles(_, _, let state), .image(_, let state), .shading(_, let state),
        .form(_, let state), .transparencyGroup(_, let state), .text(_, let state),
        .markedContent(_, let state):
        state
      case .fillAndStroke(_, _, let fillState, _): fillState
      }
    if case .pattern(.tiling(let pattern, _)) = state.paint {
      try collect(pattern.displayList.effects, depth: depth + 1)
    }
  }

  private func unicode(
    for placement: GraphicsGlyphPlacement,
    font: GraphicsFontDescription
  ) -> [UInt32]? {
    if let scalars = placement.unicodeScalars { return scalars.map(\.value) }
    if case .name(let name) = placement.glyph.selector,
      let scalars = AdobeGlyphList.unicodeScalars(for: name)
    {
      return scalars.map(\.value)
    }
    if let index = placement.glyph.resolvedGlyphIndex,
      let asset = font.asset,
      asset.format == .sfnt,
      let data = asset.data,
      let scalar = try? SFNTCharacterMap(data: data, faceIndex: asset.faceIndex)
        .uniqueUnicodeScalar(for: index)
    {
      return [scalar]
    }
    return nil
  }
}
