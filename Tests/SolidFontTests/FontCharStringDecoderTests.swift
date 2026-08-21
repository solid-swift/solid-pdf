import Foundation
import SolidFont
import Testing

@Suite struct FontCharStringDecoderTests {
  @Test func decodesType1WidthAndOutline() throws {
    let data = Data([
      139, 248, 236, 13,
      139, 139, 21,
      248, 136, 139, 5,
      139, 249, 80, 5,
      252, 136, 139, 5,
      139, 253, 80, 5,
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

  @Test func acceptsType1LegacyHintsAndDotSections() throws {
    let result = try FontCharStringDecoder.decode(
      Data([
        12, 0,
        139, 140, 141, 142, 143, 144, 12, 1,
        139, 140, 141, 142, 143, 144, 12, 2,
        149, 159, 21, 12, 0, 14,
      ]),
      dialect: .type1
    )
    #expect(result.outline.elements == [.move(FontPoint(x: 10, y: 20))])
  }

  @Test func decodesType1FlexOtherSubroutinesIntoTwoCurves() throws {
    let result = try FontCharStringDecoder.decode(
      Data([
        139, 139, 21,
        139, 140, 12, 16,
        189, 139, 21, 139, 141, 12, 16,
        99, 139, 21, 139, 141, 12, 16,
        149, 149, 21, 139, 141, 12, 16,
        169, 139, 21, 139, 141, 12, 16,
        169, 139, 21, 139, 141, 12, 16,
        149, 129, 21, 139, 141, 12, 16,
        149, 139, 21, 139, 141, 12, 16,
        149, 239, 139, 142, 139, 12, 16,
        12, 17, 12, 17, 12, 33, 14,
      ]),
      dialect: .type1
    )
    #expect(result.outline.elements == [
      .move(FontPoint(x: 0, y: 0)),
      .cubic(
        control1: FontPoint(x: 10, y: 0),
        control2: FontPoint(x: 20, y: 10),
        end: FontPoint(x: 50, y: 10)
      ),
      .cubic(
        control1: FontPoint(x: 80, y: 10),
        control2: FontPoint(x: 90, y: 0),
        end: FontPoint(x: 100, y: 0)
      ),
    ])
  }

  @Test func preservesMultipleMasterOtherSubroutineResultOrdering() throws {
    let result = try FontCharStringDecoder.decode(
      Data([149, 159, 143, 147, 143, 154, 12, 16, 12, 17, 12, 17, 21, 14]),
      dialect: .type1,
      multipleMasterWeights: [0.25]
    )
    #expect(result.outline.elements == [.move(FontPoint(x: 11, y: 22))])
  }

  @Test func type1HintReplacementAndUnknownOtherSubroutinesPreserveResults() throws {
    let hintReplacement = try FontCharStringDecoder.decode(
      Data([143, 140, 142, 12, 16, 12, 17, 10, 139, 22, 14]),
      dialect: .type1,
      localSubroutines: [Data([11]), Data([11]), Data([11]), Data([11]), Data([139, 159, 1, 11])]
    )
    #expect(hintReplacement.outline.elements == [.move(FontPoint(x: 0, y: 0))])

    let unknown = try FontCharStringDecoder.decode(
      Data([149, 159, 141, 143, 12, 16, 12, 17, 12, 17, 21, 14]),
      dialect: .type1
    )
    #expect(unknown.outline.elements == [.move(FontPoint(x: 10, y: 20))])
  }

  @Test func type2IfElseUsesSpecificationOperandOrder() throws {
    let first = try FontCharStringDecoder.decode(
      Data([149, 159, 140, 141, 12, 22, 22, 14]),
      dialect: .type2
    )
    #expect(first.outline.elements == [.move(FontPoint(x: 10, y: 0))])

    let second = try FontCharStringDecoder.decode(
      Data([149, 159, 142, 141, 12, 22, 22, 14]),
      dialect: .type2
    )
    #expect(second.outline.elements == [.move(FontPoint(x: 20, y: 0))])
  }

  @Test func type2HFlex1RestoresTheStartingYCoordinate() throws {
    let result = try FontCharStringDecoder.decode(
      Data([149, 141, 159, 142, 169, 179, 189, 143, 199, 12, 36, 14]),
      dialect: .type2
    )
    #expect(result.outline.elements == [
      .cubic(
        control1: FontPoint(x: 10, y: 2),
        control2: FontPoint(x: 30, y: 5),
        end: FontPoint(x: 60, y: 5)
      ),
      .cubic(
        control1: FontPoint(x: 100, y: 5),
        control2: FontPoint(x: 150, y: 9),
        end: FontPoint(x: 210, y: 0)
      ),
    ])
  }

  @Test func type2AcceptsDeprecatedDotSectionAndCompositeEndChar() throws {
    let result = try FontCharStringDecoder.decode(
      Data([189, 12, 0, 149, 159, 204, 205, 14]),
      dialect: .type2,
      nominalWidth: 500
    )
    #expect(result.advance == FontPoint(x: 550, y: 0))
    #expect(result.components == [
      FontCharStringComponent(characterCode: 65, offset: FontPoint(x: 0, y: 0)),
      FontCharStringComponent(characterCode: 66, offset: FontPoint(x: 10, y: 20)),
    ])
  }

  @Test func enforcesOutlineAndTerminationLimits() throws {
    let limits = try FontParsingLimits(maximumOutlineElements: 1)
    #expect(throws: FontError.limitExceeded) {
      _ = try FontCharStringDecoder.decode(
        Data([139, 22, 140, 139, 5, 14]),
        dialect: .type2,
        limits: limits
      )
    }
    #expect(throws: FontError.invalidData) {
      _ = try FontCharStringDecoder.decode(Data([139, 22]), dialect: .type2)
    }
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
