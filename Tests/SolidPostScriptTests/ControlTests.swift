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
    let result: BooleanValue = try await Interpreter.result(
      content: """
        {exit} stopped
        $error /errorname get /invalidexit eq and
        $error /command get /exit load eq and
        """
    )

    #expect(result.value)
  }

  @Test
  func testCountExecStack() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "countexecstack")
    expectEqual(res1.value, 1)

    let res2: IntegerValue = try await Interpreter.result(content: "{countexecstack exit} loop")
    expectEqual(res2.value, 3)
  }

  @Test
  func testCopyExecStack() async throws {
    let res1: ArrayValue = try await Interpreter.result(content: "10 array execstack")
    expectEqual(res1.count, 1)
    expectEqual(try res1.object(at: 0).type, .file)

    let res2: ArrayValue = try await Interpreter.result(content: "{10 array execstack exit} loop")
    expectEqual(res2.count, 3)
    expectEqual(try res2.object(at: 0).type, .file)
    expectEqual(try res2.object(at: 1), .executableName("loop"))
    expectEqual(try res2.object(at: 2).type, .array)
  }

  @Test
  func nestedLoopsCatchOnlyTheirOwnExit() async throws {
    let results: [IntegerValue] = try await Interpreter.result(
      content: "0 1 2 { 0 { 1 add exit 100 } loop add } for",
      count: 3
    )

    #expect(results.map(\.value) == [3, 2, 1])
  }

  @Test
  func everyImplementedLoopingOperatorCatchesExit() async throws {
    let repeatResult: IntegerValue = try await Interpreter.result(content: "0 10 {1 add exit} repeat")
    #expect(repeatResult.value == 1)

    let forResult: IntegerValue = try await Interpreter.result(content: "0 1 10 {exit} for")
    #expect(forResult.value == 0)

    let forAllResult: IntegerValue = try await Interpreter.result(content: "[7 8] {exit} forall")
    #expect(forAllResult.value == 7)

    let resourceForAllResult: IntegerValue = try await Interpreter.result(
      content: "(*) {pop exit} 100 string /Filter resourceforall 42"
    )
    #expect(resourceForAllResult.value == 42)
  }

  @Test
  func exitThroughANonLoopCallbackFindsTheOuterLoop() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content: """
        0 {
          1 add
          /stream {exit} /ASCIIHexDecode filter def
          stream 1 string readstring pop pop
          99
        } loop
        """
    )

    #expect(result.value == 1)
  }

  @Test
  func stoppedPreventsExitFromReachingAnOuterLoop() async throws {
    let results = try await Interpreter.results(
      content: """
        0 {
          1 add
          {exit} stopped
          $error /errorname get /invalidexit eq and
          exit
        } loop
        """
    )

    #expect(results.count == 3)
    #expect(try results[0].value(as: BooleanValue.self).value)
    #expect(results[1].value is Operators.Exit)
    #expect(try results[2].value(as: IntegerValue.self).value == 1)
  }

  @Test
  func invalidExitCanRecoverThroughACustomHandler() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content: """
        errordict /invalidexit {pop 41} put
        {exit 42} stopped not
        exch 42 eq and
        exch 41 eq and
        """
    )

    #expect(result.value)
  }

  @Test
  func executionStackLimitCountsControlBoundaries() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content: """
        << /MaxExecStack 3 >> setuserparams
        {{} loop} stopped
        $error /errorname get /execstackoverflow eq and
        """
    )

    #expect(result.value)
  }

  @Test
  func errorExecutionStackIncludesStoppedBoundary() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content: """
        {exit} stopped pop
        $error /estack get 1 get /stopped eq
        """
    )

    #expect(result.value)
  }

  @Test
  func runBlocksExitAndClosesTheFile() async throws {
    let file = DataFile(data: Data("exit".utf8), mode: .read)
    let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [RunFileDevice(file: file)]))

    let result: BooleanValue = try await Interpreter.result(
      content: """
        {(%run%program) run} stopped
        $error /errorname get /invalidexit eq and
        $error /command get /exit load eq and
        """,
      environment: environment
    )

    #expect(result.value)
    #expect(file.isClosed)
  }

  @Test
  func runAllowsAnInnerLoopToExitAndClosesNormally() async throws {
    let file = DataFile(data: Data("0 {1 add exit} loop".utf8), mode: .read)
    let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [RunFileDevice(file: file)]))

    let result: IntegerValue = try await Interpreter.result(
      content: "(%run%program) run",
      environment: environment
    )

    #expect(result.value == 1)
    #expect(file.isClosed)
  }

  @Test
  func runClosesAfterStopAndLanguageErrors() async throws {
    for (program, expectedError) in [("stop", ""), ("{", "syntaxerror")] {
      let file = DataFile(data: Data(program.utf8), mode: .read)
      let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [RunFileDevice(file: file)]))
      let source = expectedError.isEmpty
        ? "{(%run%program) run} stopped"
        : "{(%run%program) run} stopped clear $error /errorname get /\(expectedError) eq"

      let result: BooleanValue = try await Interpreter.result(content: source, environment: environment)

      #expect(result.value)
      #expect(file.isClosed)
    }
  }

  @Test
  func runClosesWhenItsExecutionBoundaryCannotBePushed() async throws {
    let file = DataFile(data: Data("1".utf8), mode: .read)
    let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [RunFileDevice(file: file)]))
    let result: BooleanValue = try await Interpreter.result(
      content: """
        << /MaxExecStack 3 >> setuserparams
        {(%run%program) run} stopped clear
        $error /errorname get /execstackoverflow eq
        """,
      environment: environment
    )

    #expect(result.value)
    #expect(file.isClosed)
  }

  @Test(.timeLimit(.minutes(1)))
  func runClosesOnCancellation() async {
    let file = DataFile(data: Data("{} loop 0".utf8), mode: .read)
    let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [RunFileDevice(file: file)]))
    let execution = Task {
      try await Interpreter.execute(content: "(%run%program) run", environment: environment)
    }

    while !file.isClosed, (try? file.offset) ?? 0 < 8 {
      await Task.yield()
    }
    #expect(!file.isClosed)
    execution.cancel()

    await #expect(throws: CancellationError.self) {
      try await execution.value
    }
    #expect(file.isClosed)
  }

  @Test
  func testQuit() async throws {
    do {
      _ = try await Interpreter.results(content: "exit")
      recordIssue("Expected an unmatched outer exit to follow the built-in quit path")
    } catch let error as Error {
      expectTrue(error == Error.control(.quit))
    }

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

private struct RunFileDevice: FileDevice {
  let file: any File

  let searched = false
  let name = "run"

  func open(name: String, mode: File.Mode, openMethod: OpenMethod) throws -> any File {
    guard name == "program", mode == .read, openMethod == .existingOnly else {
      throw Error.undefinedFilename
    }
    return file
  }
}
