//
//  TimeTests.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct TimeTests {

  @Test
  func testRealTime() async throws {
    let time1: IntegerValue = try await Interpreter.result(content: "realtime")
    let current = Int32(truncatingIfNeeded: Int64(Date.timeIntervalSinceReferenceDate * 1000))
    #expect(abs(Int64(time1.value) - Int64(current)) < 1_000)
  }

  @Test
  func testUserTime() async throws {
    let time1: IntegerValue = try await Interpreter.result(content: "usertime")
    expectLessThanOrEqual(time1.value, 500 * 1000)
  }

}
