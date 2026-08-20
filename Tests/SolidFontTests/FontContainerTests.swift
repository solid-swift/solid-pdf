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
}
