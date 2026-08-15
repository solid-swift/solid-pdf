//
//  RandomTests.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct RandomTests {

  @Test
  func testRandom() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "rand")
    expectTrue((0...Int(UInt32.max)).contains(res1.value))

    let res2: IntegerValue = try await Interpreter.result(content: "0 srand rand")
    expectEqual(res2.value, 1)
  }

  @Test
  func testGetSetRandomSeed() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "123 srand rrand")
    expectEqual(res1.value, 123)

    let sequence: [IntegerValue] = try await Interpreter.result(
      content: "123 srand rrand rand rand rrand",
      count: 4
    )
    #expect(sequence.map(\.value) == [123, 211_684_897, 3_419_675_296, 123])
  }
}
