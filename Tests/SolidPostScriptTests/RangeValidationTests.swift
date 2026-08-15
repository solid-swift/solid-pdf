//
//  RangeValidationTests.swift
//

import SolidPostScript
import Testing

@Suite
struct RangeValidationTests {

  @Test
  func zeroLengthObjectsAreValid() async throws {
    let results = try await Interpreter.result(
      content: "0 array length 0 dict length 0 string length 0 packedarray length",
      count: 4,
      as: IntegerValue.self
    )

    #expect(results.allSatisfy { $0.value == 0 })
  }

  @Test
  func invalidStackCountsProduceLanguageErrors() async throws {
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "-1 index")
    }
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "1 -1 copy")
    }
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "1 -1 0 roll")
    }
    await #expect(throws: Error.stackUnderflow) {
      try await Interpreter.execute(content: "1 2 3 5 1 roll")
    }
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "-1 packedarray")
    }

    let count: IntegerValue = try await Interpreter.result(content: "0 7 roll count")
    #expect(count.value == 0)
  }

  @Test
  func invalidCollectionRangesProduceRangeCheck() async {
    for content in [
      "[] -1 get",
      "(a) -1 get",
      "[] -1 0 getinterval",
      "[] 0 -1 getinterval",
      "[] 1 0 getinterval",
      "[] -1 [] putinterval",
    ] {
      await #expect(throws: Error.rangeCheck) {
        try await Interpreter.execute(content: content)
      }
    }
  }

  @Test
  func stringPutRequiresAByteValue() async throws {
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "(a) 0 -1 put")
    }
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "(a) 0 256 put")
    }

    let values = try await Interpreter.result(
      content: "(a) dup 0 0 put 0 get (a) dup 0 255 put 0 get",
      count: 2,
      as: IntegerValue.self
    )
    #expect(values.map(\.value) == [255, 0])
  }

  @Test
  func zeroLengthReadStringProducesRangeCheck() async {
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "currentfile 0 string readstring")
    }
  }

  @Test
  func rangeCheckUsesErrorDictionaryAndStopped() async throws {
    let results = try await Interpreter.results(
      content: "{ (a) 0 256 put } stopped $error /errorname get"
    )
    #expect(results.contains { ($0.value as? NameValue)?.value == "rangecheck" })
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
  }
}
