import Foundation
import SolidFont

extension Operators {
  static let bitmapFontOps: [OperatorValue] = [AddGlyph.instance, RemoveGlyphs.instance, RemoveAllGlyphs.instance]

  enum AddGlyph: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".addglyph"]

    func execute(context: isolated Context) async throws {
      let fontObject = try context.operands.pop()
      let cid = try context.operands.pop().value(as: IntegerValue.self).value
      let bitmap = try context.operands.pop().value(as: StringValue.self)
      let metricsObject = try context.operands.pop()
      guard cid >= 0 else { throw Error.rangeCheck }
      let font = try fontDefinition(fontObject, context: context)
      guard font.type == 32 else { throw Error.invalidFont }
      let metrics = try numericArray(metricsObject)
      guard metrics.count == 6 || metrics.count == 10 else { throw Error.rangeCheck }
      let widthValue = metrics[4] - metrics[2]
      let heightValue = metrics[5] - metrics[3]
      guard widthValue >= 0, heightValue >= 0,
        metrics[2].rounded() == metrics[2], metrics[3].rounded() == metrics[3],
        metrics[4].rounded() == metrics[4], metrics[5].rounded() == metrics[5],
        widthValue.rounded() == widthValue, heightValue.rounded() == heightValue,
        abs(metrics[2]) <= Double(Int.max), abs(metrics[5]) <= Double(Int.max),
        widthValue <= Double(Int.max), heightValue <= Double(Int.max)
      else { throw Error.rangeCheck }
      let width = Int(widthValue)
      let height = Int(heightValue)
      let rowBytes = (width + 7) / 8
      let bytes = try bitmap.characters(in: bitmap.range)
      guard height == 0 || rowBytes <= Int.max / height,
        height == 0 || width <= Int.max / height,
        bytes.count == rowBytes * height
      else {
        throw Error.rangeCheck
      }
      var coverage = Data(count: width * height)
      for row in 0..<height {
        for column in 0..<width {
          coverage[row * width + column] = bytes[row * rowBytes + column / 8] & (0x80 >> (column % 8)) == 0
            ? 0 : 255
        }
      }
      let verticalAdvance = metrics.count == 10 ? GraphicsPoint(x: metrics[6], y: metrics[7]) : nil
      let verticalOrigin = metrics.count == 10 ? GraphicsPoint(x: metrics[8], y: metrics[9]) : nil
      let selector = GraphicsGlyphSelector.cid(UInt32(cid))
      let glyph = GraphicsGlyphDescription(
        selector: selector,
        metrics: GraphicsGlyphMetrics(
          horizontalAdvance: GraphicsPoint(x: metrics[0], y: metrics[1]),
          verticalAdvance: verticalAdvance,
          verticalOrigin: verticalOrigin,
          bounds: GraphicsRect(x: metrics[2], y: metrics[3], width: widthValue, height: heightValue)
        ),
        program: .bitmap(try FontGlyphBitmap(
          width: width,
          height: height,
          bytesPerRow: width,
          originX: Int(metrics[2]),
          originY: Int(metrics[5]),
          coverage: coverage
        ))
      )
      guard context.environment.fontManager.glyphCache.insertPinned(
        glyph,
        font: font.identifier,
        selector: selector,
        maximumItemBytes: Int(context.userParameters.integer("MaxFontItem"))
      ) else { throw Error.limitCheck }
    }
  }

  enum RemoveGlyphs: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".removeglyphs"]

    func execute(context: isolated Context) async throws {
      let fontObject = try context.operands.pop()
      let last = try context.operands.pop().value(as: IntegerValue.self).value
      let first = try context.operands.pop().value(as: IntegerValue.self).value
      guard first >= 0, last >= first else { throw Error.rangeCheck }
      let font = try fontDefinition(fontObject, context: context)
      guard font.type == 32 else { throw Error.invalidFont }
      context.environment.fontManager.glyphCache.removePinned(
        font: font.identifier,
        cidRange: UInt32(first)...UInt32(last)
      )
    }
  }

  enum RemoveAllGlyphs: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".removeallglyphs"]

    func execute(context: isolated Context) async throws {
      let fontObject = try context.operands.pop()
      let font = try fontDefinition(fontObject, context: context)
      guard font.type == 32 else { throw Error.invalidFont }
      context.environment.fontManager.glyphCache.removePinned(font: font.identifier, cidRange: nil)
    }
  }
}
