//
//  RootLogExpTests.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct RootLogExpTests {

  @Test
  func testSquareRoot() async throws {
    let res1: RealValue = try await Interpreter.result(content: "4 sqrt")
    expectEqual(res1.value, 2.0)

    let res2: RealValue = try await Interpreter.result(content: "4.0 sqrt")
    expectEqual(res2.value, 2.0)
  }

  @Test
  func testExponent() async throws {
    let res1: RealValue = try await Interpreter.result(content: "2 2 exp")
    expectEqual(res1.value, 4.0)

    let res2: RealValue = try await Interpreter.result(content: "2.0 2.0 exp")
    expectEqual(res2.value, 4.0)

    let res3: RealValue = try await Interpreter.result(content: "2 2.0 exp")
    expectEqual(res3.value, 4.0)

    let res4: RealValue = try await Interpreter.result(content: "2.0 2 exp")
    expectEqual(res4.value, 4.0)
  }

  @Test
  func testNaturalLogarithm() async throws {
    let res1: RealValue = try await Interpreter.result(content: "10 ln")
    expectEqual(res1.value, log(10))

    let res2: RealValue = try await Interpreter.result(content: "100 ln")
    expectEqual(res2.value, log(100))

    let res3: RealValue = try await Interpreter.result(content: "10.0 ln")
    expectEqual(res3.value, log(10))

    let res4: RealValue = try await Interpreter.result(content: "100.0 ln")
    expectEqual(res4.value, log(100))
  }

  @Test
  func testLogarithm() async throws {
    let res1: RealValue = try await Interpreter.result(content: "10 log")
    expectEqual(res1.value, 1)

    let res2: RealValue = try await Interpreter.result(content: "100 log")
    expectEqual(res2.value, 2)

    let res3: RealValue = try await Interpreter.result(content: "10.0 log")
    expectEqual(res3.value, 1)

    let res4: RealValue = try await Interpreter.result(content: "100.0 log")
    expectEqual(res4.value, 2)
  }
}
