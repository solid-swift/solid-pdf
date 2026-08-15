//
//  ArithmeticTests.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation
import SolidPostScript
import Testing

@Suite
struct ArithmeticTests {

  @Test func testAdd() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "10 20 add")
    #expect(res1.value == (10 + 20))

    let res2: RealValue = try await Interpreter.result(content: "10.1 20.2 add")
    #expect(res2.value == (10.1 + 20.2))

    let res3: RealValue = try await Interpreter.result(content: "10.1 20 add")
    #expect(res3.value == (10.1 + 20))

    let res4: RealValue = try await Interpreter.result(content: "10 20.2 add")
    #expect(res4.value == (10 + 20.2))
  }

  @Test func testSub() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "10 20 sub")
    #expect(res1.value == (10 - 20))

    let res2: RealValue = try await Interpreter.result(content: "10.1 20.2 sub")
    #expect(res2.value == (10.1 - 20.2))

    let res3: RealValue = try await Interpreter.result(content: "10.1 20 sub")
    #expect(res3.value == (10.1 - 20))

    let res4: RealValue = try await Interpreter.result(content: "10 20.2 sub")
    #expect(res4.value == (10 - 20.2))
  }

  @Test func testMulitpy() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "10 20 mul")
    #expect(res1.value == (20 * 10))

    let res2: RealValue = try await Interpreter.result(content: "10.1 20.2 mul")
    #expect(res2.value == (10.1 * 20.2))

    let res3: RealValue = try await Interpreter.result(content: "10.1 20 mul")
    #expect(res3.value == (10.1 * 20))

    let res4: RealValue = try await Interpreter.result(content: "10 20.2 mul")
    #expect(res4.value == (10 * 20.2))
  }

  @Test func testDivide() async throws {
    let res1: RealValue = try await Interpreter.result(content: "20 10 div")
    #expect(res1.value == 2)

    let res2: RealValue = try await Interpreter.result(content: "20.2 10.1 div")
    #expect(res2.value == 2.0)

    let res3: RealValue = try await Interpreter.result(content: "20.1 10 div")
    #expect(res3.value == (20.1 / 10))

    let res4: RealValue = try await Interpreter.result(content: "10 20.2 div")
    #expect(res4.value == (10 / 20.2))
  }

  @Test func testIntegerDivide() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "3 2 idiv")
    #expect(res1.value == 1)
    let res2: IntegerValue = try await Interpreter.result(content: "4 2 idiv")
    #expect(res2.value == 2)
    let res3: IntegerValue = try await Interpreter.result(content: "-5 2 idiv")
    #expect(res3.value == -2)
  }

  @Test func testModulu() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "5 3 mod")
    #expect(res1.value == 2)
    let res2: IntegerValue = try await Interpreter.result(content: "5 2 mod")
    #expect(res2.value == 1)
    let res3: IntegerValue = try await Interpreter.result(content: "-5 3 mod")
    #expect(res3.value == -2)
  }

  @Test func testAbsoluteValue() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "5 abs")
    #expect(res1.value == 5)
    let res2: IntegerValue = try await Interpreter.result(content: "-5 abs")
    #expect(res2.value == 5)
    let res3: RealValue = try await Interpreter.result(content: "5.3 abs")
    #expect(res3.value == 5.3)
    let res4: RealValue = try await Interpreter.result(content: "-5.3 abs")
    #expect(res4.value == 5.3)
    let res5: RealValue = try await Interpreter.result(content: "\(Int32.min) abs")
    #expect(res5.value == 2_147_483_648)
  }

  @Test func testNegativeValue() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "5 neg")
    #expect(res1.value == -5)
    let res2: IntegerValue = try await Interpreter.result(content: "-5 neg")
    #expect(res2.value == 5)
    let res3: RealValue = try await Interpreter.result(content: "5.3 neg")
    #expect(res3.value == -5.3)
    let res4: RealValue = try await Interpreter.result(content: "-5.3 neg")
    #expect(res4.value == 5.3)
    let res5: RealValue = try await Interpreter.result(content: "\(Int32.min) neg")
    #expect(res5.value == 2_147_483_648)
  }

  @Test func testCeiling() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "5 ceiling")
    #expect(res1.value == 5)
    let res2: IntegerValue = try await Interpreter.result(content: "-5 ceiling")
    #expect(res2.value == -5)
    let res3: RealValue = try await Interpreter.result(content: "5.3 ceiling")
    #expect(res3.value == 6)
    let res4: RealValue = try await Interpreter.result(content: "-5.3 ceiling")
    #expect(res4.value == -5)
  }

  @Test func testFloor() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "5 floor")
    #expect(res1.value == 5)
    let res2: IntegerValue = try await Interpreter.result(content: "-5 floor")
    #expect(res2.value == -5)
    let res3: RealValue = try await Interpreter.result(content: "5.3 floor")
    #expect(res3.value == 5)
    let res4: RealValue = try await Interpreter.result(content: "-5.3 floor")
    #expect(res4.value == -6)
  }

  @Test func testRound() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "5 round")
    #expect(res1.value == 5)
    let res2: IntegerValue = try await Interpreter.result(content: "-5 round")
    #expect(res2.value == -5)
    let res3: RealValue = try await Interpreter.result(content: "5.3 round")
    #expect(res3.value == 5)
    let res4: RealValue = try await Interpreter.result(content: "-5.3 round")
    #expect(res4.value == -5)
  }

  @Test func testTruncate() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "5 truncate")
    #expect(res1.value == 5)
    let res2: IntegerValue = try await Interpreter.result(content: "-5 truncate")
    #expect(res2.value == -5)
    let res3: RealValue = try await Interpreter.result(content: "5.3 truncate")
    #expect(res3.value == 5)
    let res4: RealValue = try await Interpreter.result(content: "-5.3 truncate")
    #expect(res4.value == -5)
  }

}
