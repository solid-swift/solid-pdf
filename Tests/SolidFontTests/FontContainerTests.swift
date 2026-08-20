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
}
