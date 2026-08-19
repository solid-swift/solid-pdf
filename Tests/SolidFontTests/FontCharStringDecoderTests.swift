import Foundation
import SolidFont
import Testing

@Suite struct FontCharStringDecoderTests {
  @Test func decodesType1WidthAndOutline() throws {
    let data = Data([
      139, 248, 236, 13,
      139, 139, 21,
      248, 136, 139, 139, 249, 80, 252, 136, 139, 139, 253, 80, 5,
      9, 14,
    ])
    let result = try FontCharStringDecoder.decode(data, dialect: .type1)
    #expect(result.advance == FontPoint(x: 600, y: 0))
    #expect(result.outline.elements.count == 6)
  }

  @Test func decryptsType1DataAndRejectsShortPrefixes() throws {
    #expect(throws: FontError.invalidData) {
      _ = try FontCharStringDecoder.decryptType1(Data([1, 2]), lenIV: 4)
    }
    #expect(try FontCharStringDecoder.decryptType1(Data([1, 2]), lenIV: -1) == Data([1, 2]))
  }
}
