//
//  ControlTests.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct ControlTests {

  @Test
  func testExec() async throws {
    let res1 = try await Interpreter.results(content: "{10} exec")
    guard res1.count == 1 else {
      return recordIssue("Expected 1 operand")
    }
    expectEqual((res1[0].value as? IntegerValue)?.value, 10)
  }

  @Test
  func testIf() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "10 true {20} if")
    expectEqual(res1.value, 20)

    let res2: IntegerValue = try await Interpreter.result(content: "10 false {20} if")
    expectEqual(res2.value, 10)
  }

  @Test
  func testIfElse() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "10 true {20} {30} ifelse")
    expectEqual(res1.value, 20)

    let res2: IntegerValue = try await Interpreter.result(content: "10 false {20} {30} ifelse")
    expectEqual(res2.value, 30)
  }

  @Test
  func testFor() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "0 1 1 4 {add} for")
    expectEqual(res1.value, 10)

    let res2: [IntegerValue] = try await Interpreter.result(content: "1 2 6 { } for", count: 3)
    expectEqual(res2[0].value, 5)
    expectEqual(res2[1].value, 3)
    expectEqual(res2[2].value, 1)

    let res3: [RealValue] = try await Interpreter.result(content: "3 -.5 1 { } for", count: 5)
    expectEqual(res3[0].value, 1.0)
    expectEqual(res3[1].value, 1.5)
    expectEqual(res3[2].value, 2.0)
    expectEqual(res3[3].value, 2.5)
    expectEqual(res3[4].value, 3.0)
  }

  @Test
  func testRepeat() async throws {
    let res1: [StringValue] = try await Interpreter.result(content: "4 {(abc)} repeat", count: 4)
    expectEqual(res1[0].string, "abc")
    expectEqual(res1[1].string, "abc")
    expectEqual(res1[2].string, "abc")
    expectEqual(res1[3].string, "abc")

    let res2: IntegerValue = try await Interpreter.result(content: "1 2 3 4 3 {pop} repeat")
    expectEqual(res2.value, 1)

    let res3 = try await Interpreter.results(content: "4 {} repeat")
    expectEqual(res3.count, 0)

    let res4 = try await Interpreter.results(content: "0 {(won't happen)} repeat")
    expectEqual(res4.count, 0)
  }

  @Test
  func testLoop() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "0 {1 add dup 3 eq {exit} if} loop")
    expectEqual(res1.value, 3)
  }

  @Test
  func testStopped() async throws {
    let res1 = try await Interpreter.results(content: "{stop} stopped 10")
    guard res1.count == 2 else {
      return recordIssue("Expected 2 operands")
    }
    expectEqual((res1[0].value as? IntegerValue)?.value, 10)
    expectEqual((res1[1].value as? BooleanValue)?.value, true)

    let res2 = try await Interpreter.results(content: "{} stopped 10")
    guard res2.count == 2 else {
      return recordIssue("Expected 2 operands")
    }
    expectEqual((res2[0].value as? IntegerValue)?.value, 10)
    expectEqual((res2[1].value as? BooleanValue)?.value, false)

    let res3 = try await Interpreter.results(content: "{{stop} exec} stopped 10")
    guard res3.count == 2 else {
      return recordIssue("Expected 2 operands")
    }
    expectEqual((res3[0].value as? IntegerValue)?.value, 10)
    expectEqual((res3[1].value as? BooleanValue)?.value, true)
  }

  @Test
  func testStoppedInvalidExit() async throws {
    do {
      _ = try await Interpreter.results(content: "{exit} stopped 10")
      recordIssue("Expected invalidExit error")
    } catch let error as Error {
      expectTrue(error == Error.invalidExit)
    }
  }

  @Test
  func testCountExecStack() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "countexecstack")
    expectEqual(res1.value, 1)

    let res2: IntegerValue = try await Interpreter.result(content: "{countexecstack exit} loop")
    expectEqual(res2.value, 2)
  }

  @Test
  func testCopyExecStack() async throws {
    let res1: ArrayValue = try await Interpreter.result(content: "10 array execstack")
    expectEqual(res1.count, 1)
    expectEqual(try res1.object(at: 0).type, .file)

    let res2: ArrayValue = try await Interpreter.result(content: "{10 array execstack exit} loop")
    expectEqual(res2.count, 2)
    expectEqual(try res2.object(at: 0).type, .file)
    expectEqual(try res2.object(at: 1).type, .array)
  }

  @Test
  func testQuit() async throws {
    do {
      _ = try await Interpreter.results(content: "quit")
      recordIssue("Expected quit error")
    } catch let error as Error {
      expectTrue(error == Error.control(.quit))
    }

    do {
      _ = try await Interpreter.results(content: "{quit} stopped")
      recordIssue("Expected quit error")
    } catch let error as Error {
      expectTrue(error == Error.control(.quit))
    }

    do {
      _ = try await Interpreter.results(content: "{quit} loop")
      recordIssue("Expected quit error")
    } catch let error as Error {
      expectTrue(error == Error.control(.quit))
    }
  }

}
