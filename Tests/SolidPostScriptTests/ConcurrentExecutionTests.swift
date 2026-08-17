//
//  ConcurrentExecutionTests.swift
//

import Foundation
import Testing

@testable import SolidPostScript

@Suite
struct ConcurrentExecutionTests {

  @Test func testConcurrentVMs() async throws {
    // Run 8 independent VMs simultaneously and verify each produces correct, isolated results
    let programs: [(String, Int)] = [
      ("2 3 add", 5),
      ("10 4 sub", 6),
      ("3 7 mul", 21),
      ("100 4 idiv", 25),
      ("5 5 mul 5 add", 30),
      ("2 10 mul 3 sub", 17),
      ("9 3 idiv 2 mul", 6),
      ("1 2 add 3 mul", 9),
    ]

    try await withThrowingTaskGroup(of: (Int, Int32).self) { group in
      for (index, (program, _)) in programs.enumerated() {
        group.addTask {
          let result: IntegerValue = try await Interpreter.result(content: program)
          return (index, result.value)
        }
      }

      var results: [(Int, Int32)] = []
      for try await result in group {
        results.append(result)
      }

      let sorted = results.sorted { $0.0 < $1.0 }
      for (index, value) in sorted {
        #expect(value == Int32(programs[index].1), "VM \(index): expected \(programs[index].1), got \(value)")
      }
    }
  }

  @Test func testVMIsolation() async throws {
    // Verify that dictionary modifications in one VM don't affect another
    async let result1: IntegerValue = Interpreter.result(content: "/x 10 def x")
    async let result2: IntegerValue = Interpreter.result(content: "/x 20 def x")
    async let result3: IntegerValue = Interpreter.result(content: "/x 30 def x")

    let (v1, v2, v3) = try await (result1, result2, result3)
    #expect(v1.value == 10)
    #expect(v2.value == 20)
    #expect(v3.value == 30)
  }

  @Test func sharedDictionaryCompatibilityAliasRemainsContextIsolated() async throws {
    let environment = InterpreterEnvironment()
    async let result1: IntegerValue = Interpreter.result(
      content: "shareddict /x 10 put shareddict /x get",
      environment: environment
    )
    async let result2: IntegerValue = Interpreter.result(
      content: "shareddict /x 20 put shareddict /x get",
      environment: environment
    )
    async let result3: IntegerValue = Interpreter.result(
      content: "shareddict /x 30 put shareddict /x get",
      environment: environment
    )

    let (v1, v2, v3) = try await (result1, result2, result3)
    #expect(v1.value == 10)
    #expect(v2.value == 20)
    #expect(v3.value == 30)
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellationStopsInfiniteExecution() async {
    let task = Task {
      try await Interpreter.execute(content: "{} loop")
    }
    await Task.yield()
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test func resultExtractionPreservesOrder() async throws {
    let count = 1_024
    let results: [IntegerValue] = try await Interpreter.result(
      content: "0 1 \(count - 1) {} for",
      count: count
    )

    #expect(results.map(\.value) == Array((0..<Int32(count)).reversed()))
  }

  @Test func resultExtractionHandlesEdgeCases() async {
    let empty: [IntegerValue]? = try? await Interpreter.result(content: "", count: 0)
    #expect(empty?.isEmpty == true)

    await #expect(throws: Error.rangeCheck) {
      let _: [IntegerValue] = try await Interpreter.result(content: "", count: -1)
    }
    await #expect(throws: Error.stackUnderflow) {
      let _: [IntegerValue] = try await Interpreter.result(content: "1", count: 2)
    }
    await #expect(throws: Error.typeCheck) {
      let _: [StringValue] = try await Interpreter.result(content: "1", count: 1)
    }
  }

}
