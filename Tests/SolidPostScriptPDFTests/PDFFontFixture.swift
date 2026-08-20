import Foundation
import SolidFont

enum PDFFontFixture {
  static func trueTypeAsset() throws -> FontAsset {
    var head = Data(repeating: 0, count: 54)
    head.replaceU32(0x0001_0000, at: 0)
    head.replaceU32(0x5F0F_3CF5, at: 12)
    head.replaceU16(1_000, at: 18)
    head.replaceU16(1, at: 50)
    var maxp = Data(repeating: 0, count: 6)
    maxp.replaceU32(0x0001_0000, at: 0)
    maxp.replaceU16(2, at: 4)
    var hhea = Data(repeating: 0, count: 36)
    hhea.replaceU32(0x0001_0000, at: 0)
    hhea.replaceU16(800, at: 4)
    hhea.replaceU16(UInt16(bitPattern: -200), at: 6)
    hhea.replaceU16(2, at: 34)
    var hmtx = Data()
    for advance: UInt16 in [500, 600] {
      hmtx.appendU16(advance)
      hmtx.appendU16(0)
    }
    var glyph = Data(repeating: 0, count: 12)
    glyph.replaceU16(0, at: 0)
    glyph.replaceU16(0, at: 10)
    var loca = Data()
    for offset: UInt32 in [0, 0, 12] { loca.appendU32(offset) }
    var post = Data(repeating: 0, count: 32)
    post.replaceU32(0x0003_0000, at: 0)
    let data = sfnt([
      0x636D_6170: cmap(), 0x676C_7966: glyph, 0x6865_6164: head,
      0x6868_6561: hhea, 0x686D_7478: hmtx, 0x6C6F_6361: loca,
      0x6D61_7870: maxp, 0x706F_7374: post,
    ])
    return try FontAsset(
      descriptor: FontDescriptor(postScriptName: "SyntheticTT", unitsPerEm: 1_000),
      format: .sfnt,
      data: data
    )
  }

  private static func cmap() -> Data {
    var subtable = Data()
    subtable.appendU16(12)
    subtable.appendU16(0)
    subtable.appendU32(28)
    subtable.appendU32(0)
    subtable.appendU32(1)
    subtable.appendU32(0x41)
    subtable.appendU32(0x41)
    subtable.appendU32(1)
    var result = Data()
    result.appendU16(0)
    result.appendU16(1)
    result.appendU16(3)
    result.appendU16(10)
    result.appendU32(12)
    result.append(subtable)
    return result
  }

  private static func sfnt(_ tables: [UInt32: Data]) -> Data {
    let ordered = tables.sorted { $0.key < $1.key }
    var result = Data(repeating: 0, count: 12 + ordered.count * 16)
    result.replaceU32(0x0001_0000, at: 0)
    result.replaceU16(UInt16(ordered.count), at: 4)
    for (index, table) in ordered.enumerated() {
      while !result.count.isMultiple(of: 4) { result.append(0) }
      let offset = result.count
      result.append(table.value)
      let record = 12 + index * 16
      result.replaceU32(table.key, at: record)
      result.replaceU32(UInt32(offset), at: record + 8)
      result.replaceU32(UInt32(table.value.count), at: record + 12)
    }
    return result
  }
}

private extension Data {
  mutating func appendU16(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func appendU32(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value >> 24))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func replaceU16(_ value: UInt16, at offset: Int) {
    self[offset] = UInt8(truncatingIfNeeded: value >> 8)
    self[offset + 1] = UInt8(truncatingIfNeeded: value)
  }

  mutating func replaceU32(_ value: UInt32, at offset: Int) {
    self[offset] = UInt8(truncatingIfNeeded: value >> 24)
    self[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
    self[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
    self[offset + 3] = UInt8(truncatingIfNeeded: value)
  }
}
