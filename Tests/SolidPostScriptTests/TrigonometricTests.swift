//
//  TrigonometricTests.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct TrigonometricTests {

  @Test
  func testArcTangent() async throws {
    let res1: RealValue = try await Interpreter.result(content: "0 1 atan")
    expectEqual(res1.value, 0.0)

    let res2: RealValue = try await Interpreter.result(content: "1 0 atan")
    expectEqual(res2.value, 90.0)

    let res3: RealValue = try await Interpreter.result(content: "-100 0 atan")
    expectEqual(res3.value, 270.0)

    let res4: RealValue = try await Interpreter.result(content: "4 4 atan")
    expectEqual(res4.value, 45.0)
  }

  @Test
  func testSine() async throws {
    let res1: RealValue = try await Interpreter.result(content: "90 sin")
    expectEqual(res1.value, 1.0)

    let res2: RealValue = try await Interpreter.result(content: "0 sin")
    expectEqual(res2.value, 0.0)

    let res3: RealValue = try await Interpreter.result(content: "90.0 sin")
    expectEqual(res3.value, 1.0)

    let res4: RealValue = try await Interpreter.result(content: "0.0 sin")
    expectEqual(res4.value, 0.0)
  }

  @Test
  func testCosine() async throws {
    let res1: RealValue = try await Interpreter.result(content: "90 cos")
    expectEqual(res1.value, 0.0, accuracy: .greatestFiniteMagnitude)

    let res2: RealValue = try await Interpreter.result(content: "0 cos")
    expectEqual(res2.value, 1.0)

    let res3: RealValue = try await Interpreter.result(content: "90.0 cos")
    expectEqual(res3.value, 0.0, accuracy: .greatestFiniteMagnitude)

    let res4: RealValue = try await Interpreter.result(content: "0.0 cos")
    expectEqual(res4.value, 1.0)
  }
}
