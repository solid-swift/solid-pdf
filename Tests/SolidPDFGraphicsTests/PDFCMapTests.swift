import Foundation
import SolidFont
@testable import SolidPDFGraphics
import Testing

@Suite
struct PDFCMapTests {
  @Test
  func parsesCIDUnicodeNotdefAndWritingModeMappings() throws {
    let source = Data("""
      begincmap
      /CMapName /Owned-Test def
      /WMode 1 def
      2 begincodespacerange
      <00> <7f>
      <8100> <81ff>
      endcodespacerange
      1 begincidchar
      <20> 3
      endcidchar
      1 begincidrange
      <8100> <8102> 100
      endcidrange
      1 beginnotdefrange
      <30> <31> 7
      endnotdefrange
      2 beginbfchar
      <20> <0020>
      <8100> <D83DDE00>
      endbfchar
      endcmap
      """.utf8)

    let map = try PDFCMapParser(maximumBytes: 4_096, maximumEntries: 128).parse(source)

    #expect(map.name == "Owned-Test")
    #expect(map.writingMode == 1)
    #expect(try map.decode(Data([0x20]), from: 0).cid == 3)
    #expect(try map.decode(Data([0x81, 0x02]), from: 0).cid == 102)
    #expect(try map.decode(Data([0x30]), from: 0).notdefCID == 7)
    #expect(map.unicodeMappings[Data([0x20])] == [" ".unicodeScalars.first!])
    #expect(map.unicodeMappings[Data([0x81, 0x00])] == ["😀".unicodeScalars.first!])
  }

  @Test
  func parsesArrayAndSequentialUnicodeRanges() throws {
    let source = Data("""
      1 begincodespacerange
      <00> <ff>
      endcodespacerange
      2 beginbfrange
      <10> <12> <0041>
      <20> <21> [<00660069> <0066006c>]
      endbfrange
      """.utf8)

    let map = try PDFCMapParser(maximumBytes: 4_096, maximumEntries: 128).parse(source)

    #expect(String(map.unicodeMappings[Data([0x10])]!.map(Character.init)) == "A")
    #expect(String(map.unicodeMappings[Data([0x12])]!.map(Character.init)) == "C")
    #expect(String(map.unicodeMappings[Data([0x20])]!.map(Character.init)) == "fi")
    #expect(String(map.unicodeMappings[Data([0x21])]!.map(Character.init)) == "fl")
  }

  @Test
  func reportsIncompleteInvalidAndBoundedMappings() throws {
    let source = Data("""
      1 begincodespacerange
      <8100> <81ff>
      endcodespacerange
      """.utf8)
    let map = try PDFCMapParser(maximumBytes: 1_024, maximumEntries: 16).parse(source)

    #expect(throws: PDFCMapError.incompleteCode) {
      try map.decode(Data([0x81]), from: 0)
    }
    #expect(throws: PDFCMapError.invalidCode) {
      try map.decode(Data([0x40, 0x00]), from: 0)
    }
    #expect(throws: PDFCMapError.limitExceeded) {
      try PDFCMapParser(maximumBytes: 1_024, maximumEntries: 2).parse(Data("""
        1 begincodespacerange
        <00> <ff>
        endcodespacerange
        1 begincidrange
        <00> <02> 0
        endcidrange
        """.utf8))
    }
  }

  @Test
  func appliesSimpleEncodingDifferencesWithoutChangingOtherCodes() throws {
    var encoding = try PDFSimpleEncoding(baseName: "WinAnsiEncoding")
    try encoding.applyDifferences([.number(.integer(65)), .name("A.alt"), .name("f_f_i")])

    #expect(encoding[64].glyphName == "at")
    #expect(encoding[65].glyphName == "A.alt")
    #expect(encoding[65].unicodeScalars == ["A".unicodeScalars.first!])
    #expect(String(encoding[66].unicodeScalars!.map(Character.init)) == "ffi")
  }

  @Test
  func loadsPinnedAdobeCharacterAndUnicodeMaps() throws {
    let limits = PDFGraphicsLimits()
    let horizontal = try PDFPredefinedCMaps.characterMap(named: "GB-EUC-H", limits: limits)
    let vertical = try PDFPredefinedCMaps.characterMap(named: "UniManga-UTF8-V", limits: limits)
    let systemInfo = try FontCIDSystemInfo(registry: "Adobe", ordering: "GB1", supplement: 6)
    let loadedUnicode = try PDFPredefinedCMaps.unicodeMap(for: systemInfo, limits: limits)
    let unicode = try #require(loadedUnicode)

    #expect(try horizontal.decode(Data([0xA1, 0xA1]), from: 0).cid == 96)
    #expect(vertical.writingMode == 1)
    #expect(unicode.unicodeMappings[Data([0x00, 0x60])] == ["　".unicodeScalars.first!])
  }
}
