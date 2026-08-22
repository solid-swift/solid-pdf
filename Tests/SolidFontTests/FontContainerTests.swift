import Foundation
import SolidFont
import Testing

@Suite struct FontContainerTests {
  @Test func parsesMinimalCompactFont() throws {
    var data = Data([1, 0, 4, 4])
    data.append(contentsOf: [0, 1, 1, 1, 5])
    data.append(contentsOf: "Test".utf8)
    data.append(contentsOf: [0, 1, 1, 1, 7, 29, 0, 0, 0, 28, 17])
    data.append(contentsOf: [0, 0, 0, 0])
    data.append(contentsOf: [0, 1, 1, 1, 2, 14])

    let collection = try CompactFontCollection(data: data)
    let face = try #require(collection.faces.first)
    #expect(face.name == "Test")
    #expect(face.charStrings == [Data([14])])
    #expect(face.charset.isEmpty)
    #expect(!face.isCIDKeyed)
  }

  @Test func parsesSFNTAndCollectionDirectories() throws {
    var sfnt = Data([0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
    sfnt.append(contentsOf: [0x68, 0x65, 0x61, 0x64, 0, 0, 0, 0, 0, 0, 0, 28, 0, 0, 0, 4])
    sfnt.append(contentsOf: [1, 2, 3, 4])

    let collection = try SFNTCollection(data: sfnt)
    let face = try #require(collection.faces.first)
    #expect(face.tables[0x6865_6164]?.length == 4)
    #expect(try face.data(for: 0x6865_6164, in: sfnt) == Data([1, 2, 3, 4]))
  }

  @Test func rejectsTruncatedAndOverLimitContainers() throws {
    #expect(throws: FontError.unsupportedFormat) {
      _ = try SFNTCollection(data: Data(repeating: 0, count: 12))
    }
    let limits = try FontParsingLimits(maximumDataBytes: 4)
    #expect(throws: FontError.limitExceeded) {
      _ = try CompactFontCollection(data: Data(repeating: 1, count: 5), limits: limits)
    }
  }

  @Test func readsSFNTEmbeddingRestrictionsAndBuildsStablePlans() throws {
    var sfnt = Data([0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
    sfnt.append(contentsOf: [0x4F, 0x53, 0x2F, 0x32, 0, 0, 0, 0, 0, 0, 0, 28, 0, 0, 0, 10])
    sfnt.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0x03, 0x02])
    let descriptor = try FontDescriptor(postScriptName: "Restricted", unitsPerEm: 1_000)
    let asset = try FontAsset(descriptor: descriptor, format: .sfnt, data: sfnt)
    let permissions = try FontSubsetter.permissions(for: asset)
    #expect(permissions.allowsEmbedding == false)
    #expect(permissions.allowsSubsetting == false)
    #expect(permissions.bitmapOnly)
    let first = try FontSubsetter.plan(asset: asset, glyphs: [7, 2, 7])
    let second = try FontSubsetter.plan(asset: asset, glyphs: [2, 7])
    #expect(first.strategy == .portableGlyphs)
    #expect(first.subsetPrefix == second.subsetPrefix)
    #expect(first.glyphs == [2, 7])
  }

  @Test func subsetsNameKeyedCompactFontsDeterministically() throws {
    var data = Data([1, 0, 4, 4])
    data.append(contentsOf: [0, 1, 1, 1, 5])
    data.append(contentsOf: "Test".utf8)
    data.append(contentsOf: [0, 1, 1, 1, 7, 29, 0, 0, 0, 28, 17])
    data.append(contentsOf: [0, 0, 0, 0])
    data.append(contentsOf: [0, 3, 1, 1, 2, 3, 4, 14, 14, 14])
    let descriptor = try FontDescriptor(postScriptName: "Test", unitsPerEm: 1_000)
    let asset = try FontAsset(descriptor: descriptor, format: .compactFontFormat, data: data)

    let first = try FontSubsetter.subset(asset, request: FontSubsetRequest(glyphIndexes: [2]))
    let second = try FontSubsetter.subset(asset, request: FontSubsetRequest(glyphIndexes: [2]))

    #expect(first == second)
    #expect(first.format == .nameKeyedCFF)
    #expect(first.glyphMapping == [0: 0, 2: 1])
    #expect(try CompactFontCollection(data: first.data).faces[0].charStrings.count == 2)
    #expect(try FontSubsetter.plan(asset: asset, glyphs: [2]).strategy == .subsetFont)
  }

  @Test func renamesPFAProgramsAndReportsSegments() throws {
    let data = Data("%!PS-AdobeFont-1.0: Fixture 1.0\n/FontName /Fixture def\neexec\n0000\ncleartomark\n".utf8)
    let descriptor = try FontDescriptor(postScriptName: "Fixture")
    let asset = try FontAsset(descriptor: descriptor, format: .type1, data: data)
    let subset = try FontSubsetter.subset(asset, request: FontSubsetRequest(glyphIndexes: [3]))

    #expect(subset.format == .type1)
    #expect(String(decoding: subset.data, as: UTF8.self).contains("/FontName /\(subset.postScriptName)"))
    #expect(subset.type1SegmentLengths?.first == subset.data.count)
  }

  @Test func decodesCMapAndAdobeGlyphNames() throws {
    var cmap = Data([0, 0, 0, 1, 0, 3, 0, 10, 0, 0, 0, 12])
    cmap.append(contentsOf: [0, 12, 0, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 1])
    cmap.append(contentsOf: [0, 1, 0xF6, 0, 0, 1, 0xF6, 0, 0, 0, 0, 7])
    var sfnt = Data([0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
    sfnt.append(contentsOf: [0x63, 0x6D, 0x61, 0x70, 0, 0, 0, 0, 0, 0, 0, 28])
    sfnt.append(contentsOf: [0, 0, 0, UInt8(cmap.count)])
    sfnt.append(cmap)

    let map = try SFNTCharacterMap(data: sfnt)
    #expect(map.mappings[0x1F600] == 7)
    #expect(map.uniqueUnicodeScalar(for: 7) == 0x1F600)
    #expect(AdobeGlyphList.unicodeScalars(for: "A.swash") == ["A".unicodeScalars.first!])
    #expect(AdobeGlyphList.unicodeScalars(for: "f_i") == ["f".unicodeScalars.first!, "i".unicodeScalars.first!])
    #expect(AdobeGlyphList.unicodeScalars(for: "u1F600") == [Unicode.Scalar(0x1F600)!])
  }

  @Test func subsetsTrueTypeGlyphsAndCompositeClosure() throws {
    let data = makeTrueTypeFixture()
    let descriptor = try FontDescriptor(postScriptName: "SyntheticTT", unitsPerEm: 1_000)
    let asset = try FontAsset(descriptor: descriptor, format: .sfnt, data: data)
    let subset = try FontSubsetter.subset(
      asset,
      request: FontSubsetRequest(glyphIndexes: [2], preservesHints: false)
    )

    #expect(subset.format == .trueType)
    #expect(subset.glyphMapping == [0: 0, 1: 1, 2: 2])
    let collection = try SFNTCollection(data: subset.data)
    let maxpData = try collection.faces[0].data(for: 0x6D61_7870, in: subset.data)
    let maxp = try #require(maxpData)
    #expect(maxp[4] == 0 && maxp[5] == 3)
    let cmap = try SFNTCharacterMap(data: subset.data)
    #expect(cmap.mappings[0x41] == 1)
    #expect(cmap.mappings[0x42] == 2)
  }

  @Test func decodesPortableTrueTypeGlyphMetricsAndCMapSelection() throws {
    let data = makeTrueTypeFixture()
    let collection = try SFNTCollection(data: data)

    #expect(try collection.glyphIndex(data: data, faceIndex: 0, unicodeScalar: "A") == 1)
    let glyph = try collection.glyph(
      data: data,
      faceIndex: 0,
      glyphIndex: 1,
      selector: .name("A")
    )
    #expect(glyph.resolvedGlyphIndex == 1)
    #expect(glyph.metrics.horizontalAdvance == FontPoint(x: 600, y: 0))
    #expect(glyph.program == .empty)
  }
}

private func makeTrueTypeFixture() -> Data {
  var head = Data(repeating: 0, count: 54)
  head.testReplaceU32(0x0001_0000, at: 0)
  head.testReplaceU32(0x5F0F_3CF5, at: 12)
  head.testReplaceU16(1_000, at: 18)
  head.testReplaceU16(1, at: 50)
  var maxp = Data(repeating: 0, count: 6)
  maxp.testReplaceU32(0x0001_0000, at: 0)
  maxp.testReplaceU16(4, at: 4)
  var hhea = Data(repeating: 0, count: 36)
  hhea.testReplaceU32(0x0001_0000, at: 0)
  hhea.testReplaceU16(800, at: 4)
  hhea.testReplaceU16(UInt16(bitPattern: -200), at: 6)
  hhea.testReplaceU16(4, at: 34)
  var hmtx = Data()
  for advance: UInt16 in [500, 600, 700, 800] {
    hmtx.testAppendU16(advance)
    hmtx.testAppendU16(0)
  }
  var simple = Data(repeating: 0, count: 12)
  simple.testReplaceU16(0, at: 0)
  simple.testReplaceU16(0, at: 10)
  var composite = Data(repeating: 0, count: 18)
  composite.testReplaceU16(0xFFFF, at: 0)
  composite.testReplaceU16(1, at: 10)
  composite.testReplaceU16(1, at: 12)
  var glyf = Data()
  glyf.append(simple)
  glyf.append(composite)
  var loca = Data()
  for offset: UInt32 in [0, 0, 12, 30, 30] { loca.testAppendU32(offset) }
  let cmap = makeCMapFixture()
  var post = Data(repeating: 0, count: 32)
  post.testReplaceU32(0x0003_0000, at: 0)
  return makeSFNTFixture([
    0x636D_6170: cmap, 0x676C_7966: glyf, 0x6865_6164: head,
    0x6868_6561: hhea, 0x686D_7478: hmtx, 0x6C6F_6361: loca,
    0x6D61_7870: maxp, 0x706F_7374: post,
  ])
}

private func makeCMapFixture() -> Data {
  var subtable = Data()
  subtable.testAppendU16(12)
  subtable.testAppendU16(0)
  subtable.testAppendU32(28)
  subtable.testAppendU32(0)
  subtable.testAppendU32(1)
  subtable.testAppendU32(0x41)
  subtable.testAppendU32(0x42)
  subtable.testAppendU32(1)
  var result = Data()
  result.testAppendU16(0)
  result.testAppendU16(1)
  result.testAppendU16(3)
  result.testAppendU16(10)
  result.testAppendU32(12)
  result.append(subtable)
  return result
}

private func makeSFNTFixture(_ tables: [UInt32: Data]) -> Data {
  let ordered = tables.sorted { $0.key < $1.key }
  var result = Data(repeating: 0, count: 12 + ordered.count * 16)
  result.testReplaceU32(0x0001_0000, at: 0)
  result.testReplaceU16(UInt16(ordered.count), at: 4)
  for (index, table) in ordered.enumerated() {
    while !result.count.isMultiple(of: 4) { result.append(0) }
    let offset = result.count
    result.append(table.value)
    let record = 12 + index * 16
    result.testReplaceU32(table.key, at: record)
    result.testReplaceU32(UInt32(offset), at: record + 8)
    result.testReplaceU32(UInt32(table.value.count), at: record + 12)
  }
  return result
}

private extension Data {
  mutating func testAppendU16(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func testAppendU32(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value >> 24))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func testReplaceU16(_ value: UInt16, at offset: Int) {
    self[offset] = UInt8(truncatingIfNeeded: value >> 8)
    self[offset + 1] = UInt8(truncatingIfNeeded: value)
  }

  mutating func testReplaceU32(_ value: UInt32, at offset: Int) {
    self[offset] = UInt8(truncatingIfNeeded: value >> 24)
    self[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
    self[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
    self[offset + 3] = UInt8(truncatingIfNeeded: value)
  }
}
