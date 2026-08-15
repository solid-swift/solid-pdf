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
    expectLessThanOrEqual(time1.value, Int(Date.timeIntervalSinceReferenceDate / 1000))
  }

  @Test
  func testUserTime() async throws {
    let time1: IntegerValue = try await Interpreter.result(content: "usertime")
    expectLessThanOrEqual(time1.value, 500 * 1000)
  }

}
