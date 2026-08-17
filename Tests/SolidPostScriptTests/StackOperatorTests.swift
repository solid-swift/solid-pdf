//
//  StackOperatorTests.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct StackOperatorTests {

  @Test
  func testPop() async throws {
    let results = try await Interpreter.results(content: "123 pop")
    expectTrue(results.isEmpty)
  }

  @Test
  func testExchange() async throws {
    let (op1, op2) = try await Interpreter.result(content: "123 456 exch", as: (IntegerValue, IntegerValue).self)
    expectEqual(op1.value, 123)
    expectEqual(op2.value, 456)
  }

  @Test
  func testDuplicate() async throws {
    let (op1, op2) = try await Interpreter.result(content: "123 dup", as: (IntegerValue, IntegerValue).self)
    expectEqual(op1.value, 123)
    expectEqual(op2.value, 123)
  }

  @Test
  func testCopy() async throws {
    let ops = try await Interpreter.result(content: "1 2 3 4 5 3 copy", count: 8, as: IntegerValue.self)
    expectEqual(ops[0].value, 5)
    expectEqual(ops[1].value, 4)
    expectEqual(ops[2].value, 3)
    expectEqual(ops[3].value, 5)
    expectEqual(ops[4].value, 4)
    expectEqual(ops[5].value, 3)
    expectEqual(ops[6].value, 2)
    expectEqual(ops[7].value, 1)
  }

  @Test
  func testIndex() async throws {
    let op = try await Interpreter.result(content: "1 2 3 4 5 2 index", as: IntegerValue.self)
    expectEqual(op.value, 3)
  }

  @Test
  func testRoll() async throws {
    let ops = try await Array(Interpreter.result(content: "1 2 3 4 5 3 2 roll", count: 5, as: IntegerValue.self))
    expectEqual(ops[0].value, 3)
    expectEqual(ops[1].value, 5)
    expectEqual(ops[2].value, 4)
    expectEqual(ops[3].value, 2)
    expectEqual(ops[4].value, 1)

    let ops2 = try await Array(Interpreter.result(content: "(a)(b)(c) 3 -1 roll", count: 3, as: StringValue.self))
    expectEqual(ops2[0].string, "a")
    expectEqual(ops2[1].string, "c")
    expectEqual(ops2[2].string, "b")

    let ops3 = try await Array(Interpreter.result(content: "(a)(b)(c) 3 1 roll", count: 3, as: StringValue.self))
    expectEqual(ops3[0].string, "b")
    expectEqual(ops3[1].string, "a")
    expectEqual(ops3[2].string, "c")

    let ops4 = try await Array(Interpreter.result(content: "(a)(b)(c) 3 0 roll", count: 3, as: StringValue.self))
    expectEqual(ops4[0].string, "c")
    expectEqual(ops4[1].string, "b")
    expectEqual(ops4[2].string, "a")
  }

  @Test
  func clearToMarkRemovesTheNearestMarkAndObjectsAboveIt() async throws {
    let loneMarkResults = try await Interpreter.results(content: "1 mark cleartomark")
    #expect(loneMarkResults == [.integer(1)])

    let nestedResults = try await Interpreter.results(content: "1 mark 2 mark 3 cleartomark")
    #expect(nestedResults.count == 3)
    #expect(try nestedResults[0].value(as: IntegerValue.self).value == 2)
    #expect(nestedResults[1].type == .mark)
    #expect(try nestedResults[2].value(as: IntegerValue.self).value == 1)
  }

  @Test
  func clearToMarkReportsUnmatchedMarkWithoutPartialMutation() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content: """
        {1 2 cleartomark} stopped clear
        $error /errorname get /unmatchedmark eq
        $error /command get /cleartomark load eq and
        """
    )

    #expect(result.value)
  }

}
