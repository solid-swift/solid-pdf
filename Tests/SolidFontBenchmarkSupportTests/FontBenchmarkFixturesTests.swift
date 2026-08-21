import SolidFont
import SolidFontBenchmarkSupport
import Testing

@Suite struct FontBenchmarkFixturesTests {
  @Test func checkedInFixturesRemainValid() throws {
    let compact = try CompactFontCollection(data: FontBenchmarkFixtures.compactFont)
    #expect(compact.faces.count == 1)
    #expect(compact.faces[0].charStrings.count == 1)

    let collection = try SFNTCollection(data: FontBenchmarkFixtures.fontCollection)
    #expect(collection.faces.count == 16)

    let type1 = try FontCharStringDecoder.decode(
      FontBenchmarkFixtures.type1CharString,
      dialect: .type1
    )
    #expect(type1.advance.x == 600)

    let type2 = try FontCharStringDecoder.decode(
      FontBenchmarkFixtures.type2CharString,
      dialect: .type2
    )
    #expect(!type2.outline.elements.isEmpty)
  }
}
