//
//  Ascii85Tests.swift
//
//
//  Created by Kevin Wooten on 6/26/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct Ascii85Tests {

  @Test
  func testRoundtrip() async throws {

    let input = Data((0..<20).map(UInt8.init))

    let encoded = Ascii85.encode(input)
    let output = try Ascii85.decode(encoded)

    expectEqual(input, output)
  }

  @Test(arguments: 0...8)
  func testRoundtripEveryFinalTupleLength(length: Int) throws {
    let input = Data((0..<length).map(UInt8.init))
    #expect(try Ascii85.decode(Ascii85.encode(input)) == input)
  }

  @Test
  func testWhitespacePartialTuplesAndZeroShorthand() throws {
    #expect(try Ascii85.decode("") == Data())
    #expect(try Ascii85.decode("!!") == Data([0]))
    #expect(try Ascii85.decode("!!!") == Data([0, 0]))
    #expect(try Ascii85.decode("!!!!") == Data([0, 0, 0]))
    #expect(try Ascii85.decode(" \t\r\n\u{0C}\u{0}z ") == Data(repeating: 0, count: 4))
  }

  @Test(arguments: ["!", "!z", "uuuuu", "v!!!!", "é"])
  func testMalformedInput(_ input: String) {
    #expect(throws: Ascii85.DecodingError.self) {
      try Ascii85.decode(input)
    }
  }

}
