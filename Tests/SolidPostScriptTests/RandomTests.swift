//
//  RandomTests.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct RandomTests {

  @Test
  func testRandom() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "rand")
    expectTrue((Int32(0)...Int32.max).contains(res1.value))

    let res2: IntegerValue = try await Interpreter.result(content: "0 srand rand")
    expectEqual(res2.value, 1)
  }

  @Test
  func testGetSetRandomSeed() async throws {
    let res1: IntegerValue = try await Interpreter.result(content: "123 srand rrand")
    expectEqual(res1.value, 123)

    let sequence: [IntegerValue] = try await Interpreter.result(
      content: "123 srand rrand rand rand rrand",
      count: 4
    )
    #expect(sequence.map(\.value) == [211_684_897, 211_684_897, 1_272_191_648, 123])
  }

  @Test
  func randomStateCanResumeFromTheExactSequencePosition() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content: """
        123 srand
        rand pop
        rrand /checkpoint exch def
        rand /expected exch def
        checkpoint srand
        rand expected eq
        """
    )

    #expect(result.value)
  }

  @Test
  func getRandomStateDoesNotAdvanceAndPreservesSignedBitPatterns() async throws {
    let unchanged: BooleanValue = try await Interpreter.result(content: "123 srand rrand rrand eq")
    #expect(unchanged.value)

    let negativeSeed: BooleanValue = try await Interpreter.result(content: "-1 srand rrand -1 eq")
    #expect(negativeSeed.value)

    let advancedState: IntegerValue = try await Interpreter.result(content: "123 srand rand pop rrand")
    #expect(advancedState.value == -875_292_000)
  }

  @Test
  func randomStateRemainsIsolatedAcrossConcurrentContexts() async throws {
    let environment = InterpreterEnvironment()

    try await withThrowingTaskGroup(of: Int32.self) { group in
      for _ in 0..<8 {
        group.addTask {
          let result: IntegerValue = try await Interpreter.result(
            content: "123 srand rand pop rrand",
            environment: environment
          )
          return result.value
        }
      }

      for try await state in group {
        #expect(state == -875_292_000)
      }
    }
  }
}
