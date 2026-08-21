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

  @Test func decryptsPublishedType1CharStringCiphertext() throws {
    let ciphertext = try #require(Data(
      hexadecimal: "10BF31704FAB5B1F03F9B68B1F39A66521B1841F1481697F8E12B7F7DDD6E3D7248D965B1CD45E2114"
    ))
    let expected = try #require(Data(
      hexadecimal: "BDF9B40D8BEF038BEF01F8ECEF018B16F95006EF07FCEC06F88807F8EC06EF07FD5006090E"
    ))
    #expect(try FontCharStringDecoder.decryptType1(ciphertext) == expected)
  }

  @Test func type2ArithmeticAndSubroutineOperandsRemainAvailable() throws {
    let arithmetic = try FontCharStringDecoder.decode(
      Data([141, 142, 12, 10, 143, 12, 24, 22, 14]),
      dialect: .type2
    )
    #expect(arithmetic.outline.elements == [.move(FontPoint(x: 20, y: 0))])

    let subroutine = try FontCharStringDecoder.decode(
      Data([32, 10, 22, 14]),
      dialect: .type2,
      localSubroutines: [Data([141, 11])]
    )
    #expect(subroutine.outline.elements == [.move(FontPoint(x: 2, y: 0))])
  }

  @Test func decodesType1CompositeComponents() throws {
    let result = try FontCharStringDecoder.decode(
      Data([139, 149, 159, 204, 205, 12, 6, 14]),
      dialect: .type1
    )
    #expect(result.components == [
      FontCharStringComponent(characterCode: 65, offset: FontPoint(x: 0, y: 0)),
      FontCharStringComponent(characterCode: 66, offset: FontPoint(x: 10, y: 20)),
    ])
  }
}

private extension Data {
  init?(hexadecimal: String) {
    guard hexadecimal.count.isMultiple(of: 2) else { return nil }
    self.init(capacity: hexadecimal.count / 2)
    var index = hexadecimal.startIndex
    while index < hexadecimal.endIndex {
      let end = hexadecimal.index(index, offsetBy: 2)
      guard let byte = UInt8(hexadecimal[index..<end], radix: 16) else { return nil }
      append(byte)
      index = end
    }
  }
}
