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

    let input = Data((0..<20).map { _ in UInt8.random(in: 0 ..< .max) })

    let encoded = Ascii85.encode(input)
    let output = try Ascii85.decode(encoded)

    expectEqual(input, output)
  }

}
