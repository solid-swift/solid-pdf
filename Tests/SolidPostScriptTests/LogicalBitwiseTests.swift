//
//  LogicalBitwiseTests.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct LogicalBitwiseTests {

  // MARK: Logical & Bitwise And (and)

  @Test
  func testAndBools() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "true true and")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "true false and")
    expectEqual(bool2.value, false)
  }

  @Test
  func testAndInts() async throws {

    let int1: IntegerValue = try await Interpreter.result(content: "16#a5a5 16#ffff and")
    expectEqual(int1.value, 0xa5a5)

    let int2: IntegerValue = try await Interpreter.result(content: "16#a5a5 0 and")
    expectEqual(int2.value, 0)
  }

  // MARK: Not (not)

  @Test
  func testNotBools() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "true not")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "false not")
    expectEqual(bool2.value, true)
  }

  @Test
  func testNotInts() async throws {

    let int1: IntegerValue = try await Interpreter.result(content: "16#a5a5 not")
    expectEqual(int1.value, Int(bitPattern: 0xffffffffffff5a5a))

    let int2: IntegerValue = try await Interpreter.result(content: "16#0000 not")
    expectEqual(int2.value, Int(bitPattern: .max))
  }

  // MARK: Or (or)

  @Test
  func testOrBools() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "true true or")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "false true or")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "false false or")
    expectEqual(bool3.value, false)
  }

  @Test
  func testOrInts() async throws {

    let int1: IntegerValue = try await Interpreter.result(content: "0 16#a5a5 or")
    expectEqual(int1.value, Int(bitPattern: 0xa5a5))

    let int2: IntegerValue = try await Interpreter.result(content: "16#5a5a 0 or")
    expectEqual(int2.value, Int(bitPattern: 0x5a5a))
  }

  // MARK: Exclusive Or (xor)

  @Test
  func testXorBools() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "true false xor")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "false true xor")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "true true xor")
    expectEqual(bool3.value, false)

    let bool4: BooleanValue = try await Interpreter.result(content: "false false xor")
    expectEqual(bool4.value, false)
  }

  @Test
  func testXorInts() async throws {

    let int1: IntegerValue = try await Interpreter.result(content: "16#ffff 16#a5a5 xor")
    expectEqual(int1.value, Int(bitPattern: 0x5a5a))

    let int2: IntegerValue = try await Interpreter.result(content: "16#5a5a 16#5a5a xor")
    expectEqual(int2.value, Int(bitPattern: 0))
  }

  // MARK: Bit Shift (bitshift)

  @Test
  func testBitShift() async throws {

    let int1: IntegerValue = try await Interpreter.result(content: "16#5555 1 bitshift")
    expectEqual(int1.value, Int(bitPattern: 0xaaaa))

    let int2: IntegerValue = try await Interpreter.result(content: "16#aaaa -1 bitshift")
    expectEqual(int2.value, Int(bitPattern: 0x5555))
  }

}
