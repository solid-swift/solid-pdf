//
//  NumericSemanticsTests.swift
//

import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct NumericSemanticsTests {

  @Test
  func boundedPublicValuesRejectInvalidHostNumbers() throws {
    #expect(IntegerValue(exactly: Int.max) == nil)
    #expect(IntegerValue(exactly: Int32.max)?.value == .max)
    #expect(RealValue(finite: .infinity) == nil)
    #expect(RealValue(finite: .nan) == nil)
    #expect(RealValue(finite: .greatestFiniteMagnitude)?.value == .greatestFiniteMagnitude)
  }

  @Test
  func decimalIntegersPromoteAtInt32Boundaries() throws {
    #expect(try scan("2147483647") == [.integer(.max)])
    #expect(try scan("-2147483648") == [.integer(.min)])
    #expect(try scan("2147483648") == [.real(2_147_483_648)])
    #expect(try scan("-2147483649") == [.real(-2_147_483_649)])
  }

  @Test
  func radixNumbersUseUnsignedInt32BitPatterns() throws {
    #expect(try scan("16#7FFFFFFF") == [.integer(.max)])
    #expect(try scan("16#80000000") == [.integer(.min)])
    #expect(try scan("16#FFFFFFFF") == [.integer(-1)])
    #expect(throws: Error.limitCheck) {
      try scan("16#100000000")
    }
  }

  @Test
  func malformedNumericTokensRemainNames() throws {
    #expect(try scan("1#1 2#2 23A") == [
      .name("1#1", kind: .executable),
      .name("2#2", kind: .executable),
      .name("23A", kind: .executable),
    ])
  }

  @Test
  func scannerRejectsRealOverflowAndUnderflow() {
    #expect(throws: Error.limitCheck) {
      try scan("1e400")
    }
    #expect(throws: Error.limitCheck) {
      try scan("1e-400")
    }
  }

  @Test
  func integerArithmeticPromotesOverflowToReal() async throws {
    let sum: RealValue = try await Interpreter.result(content: "2147483647 1 add")
    let difference: RealValue = try await Interpreter.result(content: "-2147483648 1 sub")
    let product: RealValue = try await Interpreter.result(content: "50000 50000 mul")

    #expect(sum.value == 2_147_483_648)
    #expect(difference.value == -2_147_483_649)
    #expect(product.value == 2_500_000_000)
  }

  @Test
  func realArithmeticRejectsOverflowAndUnderflow() async {
    await #expect(throws: Error.undefinedResult) {
      try await Interpreter.execute(content: "1e308 1e308 add")
    }
    await #expect(throws: Error.undefinedResult) {
      try await Interpreter.execute(content: "1e-300 1e-300 mul")
    }
  }

  @Test(arguments: ["1 0 div", "1 -0.0 div", "1 0 idiv", "1 0 mod", "-2147483648 -1 idiv"])
  func divisionErrorsAreUndefinedResult(_ program: String) async {
    await #expect(throws: Error.undefinedResult) {
      try await Interpreter.execute(content: program)
    }
  }

  @Test
  func minimumIntegerRemainderDoesNotTrap() async throws {
    let result: IntegerValue = try await Interpreter.result(content: "-2147483648 -1 mod")
    #expect(result.value == 0)
  }

  @Test
  func conversionsAndRoundingFollowPLRMRules() async throws {
    let values = try await Interpreter.results(content: "-47.8 cvi 47.8 cvi -6.5 round 6.5 round")

    #expect(try values[0].value(as: RealValue.self).value == 7)
    #expect(try values[1].value(as: RealValue.self).value == -6)
    #expect(try values[2].value(as: IntegerValue.self).value == 47)
    #expect(try values[3].value(as: IntegerValue.self).value == -47)

    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "2147483648.0 cvi")
    }
  }

  @Test(arguments: ["-1 sqrt", "0 ln", "-1 log"])
  func domainErrorsAreRangeCheck(_ program: String) async {
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: program)
    }
  }

  @Test(arguments: ["0 0 atan", "-9 0.5 exp", "1e308 2 exp", "1e-300 2 exp"])
  func meaninglessMathResultsAreUndefinedResult(_ program: String) async {
    await #expect(throws: Error.undefinedResult) {
      try await Interpreter.execute(content: program)
    }
  }

  @Test
  func mixedEqualityIsSymmetricAndMathematical() async throws {
    let values: [BooleanValue] = try await Interpreter.result(
      content: "4 4.2 eq 4.2 4 eq 4 4.0 eq 4.0 4 eq",
      count: 4
    )

    #expect(values.map(\.value) == [true, true, false, false])
  }

  @Test
  func equalNumericObjectsShareHashAndDictionaryKeys() async throws {
    let integer: Object = .integer(4)
    let real = try #require(Object.real(finite: 4.0))
    #expect(integer == real)
    #expect(Set([integer, real]).count == 1)

    let value: StringValue = try await Interpreter.result(content: "1 dict dup 4 (value) put 4.0 get")
    #expect(value.string == "value")
  }

  @Test
  func bitwiseOperatorsUseInt32BitPatterns() async throws {
    let values: [IntegerValue] = try await Interpreter.result(
      content: "0 not -1 1 bitshift 16#80000000 -1 bitshift 1 32 bitshift 1 -32 bitshift",
      count: 5
    )

    #expect(values.map(\.value) == [0, 0, 1_073_741_824, -2, -1])
  }

  @Test
  func integerForLoopCannotOverflowTheHost() async throws {
    let values: [IntegerValue] = try await Interpreter.result(
      content: "2147483646 1 2147483647 {} for",
      count: 2
    )
    #expect(values.map(\.value) == [.max, 2_147_483_646])
  }

  @Test
  func numericErrorsUseErrorDictionaryAndStopped() async throws {
    let results = try await Interpreter.results(
      content:
        """
        {1 0 idiv} stopped clear
        $error /errorname get
        $error /command get
        """
    )

    #expect(results[0].value is Operators.IntegerDivide)
    #expect(try results[1].value(as: NameValue.self).value == "undefinedresult")
  }

  @Test
  func customNumericErrorHandlerCanRecover() async throws {
    let values: [IntegerValue] = try await Interpreter.result(
      content: "errordict /undefinedresult {pop pop pop 42} put 1 0 div 7",
      count: 2
    )
    #expect(values.map(\.value) == [7, 42])
  }

  private func scan(_ content: String) throws -> [Token] {
    let scanner = try Scanner(content: Data(content.utf8))
    var tokens: [Token] = []
    while let token = try scanner.nextToken() {
      tokens.append(token)
    }
    return tokens
  }
}
