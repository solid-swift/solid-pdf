//
//  AttributeTests.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct AttributeTests {

  @Test
  func testType() async throws {
    let cases = [
      ("true", "booleantype"),
      ("10", "integertype"),
      ("10.1", "realtype"),
      ("/a", "nametype"),
      ("/add load", "operatortype"),
      ("mark", "marktype"),
      ("()", "stringtype"),
      ("[]", "arraytype"),
      ("<< >>", "dicttype"),
      ("{}", "arraytype"),
      ("1 1 packedarray", "packedarraytype"),
      ("null", "nulltype"),
    ]

    for (operand, expectedType) in cases {
      let results = try await Interpreter.results(content: "\(operand) type")
      #expect(results.count == 1)
      let type = try #require(results.first?.value as? NameValue)
      #expect(type.value == expectedType)
      #expect(results.first?.kind == .executable)
    }
  }

  @Test
  func testChangeToLiteral() async throws {
    let res1 = try await Interpreter.results(content: "{} cvlit")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .literal)
  }

  @Test
  func testChangeToExecutable() async throws {
    let res1 = try await Interpreter.results(content: "(a) cvx")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .string)
    expectEqual(res1[0].kind, .executable)
  }

  @Test
  func testReduceToExecuteOnly() async throws {
    let res1 = try await Interpreter.results(content: "{} executeonly")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .executable)
    expectEqual((res1[0].value as? ArrayValue)?.access, .executeOnly)

    do {
      _ = try await Interpreter.results(content: "[] noaccess executeonly")
      recordIssue("Expected invalidAccess error")
    } catch let error as Error {
      expectTrue(error == Error.invalidAccess)
    }
  }

  @Test
  func testReduceToReadOnly() async throws {
    let res1 = try await Interpreter.results(content: "{} readonly")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .executable)
    expectEqual((res1[0].value as? ArrayValue)?.access, .readOnly)

    do {
      _ = try await Interpreter.results(content: "[] executeonly readonly")
      recordIssue("Expected invalidAccess error")
    } catch let error as Error {
      expectTrue(error == Error.invalidAccess)
    }
  }

  @Test
  func testReduceToNoAccess() async throws {
    let res1 = try await Interpreter.results(content: "{} noaccess")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .executable)
    expectEqual((res1[0].value as? ArrayValue)?.access, .noAccess)
  }

  @Test
  func accessReductionOperatorsAcceptOnlyTheirSpecifiedCompositeTypes() async throws {
    let commonOperands = [
      ("[]", "arraytype"),
      ("0 packedarray", "packedarraytype"),
      ("(%stdout) (w) file", "filetype"),
      ("()", "stringtype"),
    ]

    for (operand, type) in commonOperands {
      for operation in ["executeonly", "readonly", "noaccess"] {
        let result: BooleanValue = try await Interpreter.result(
          content: "\(operand) \(operation) type /\(type) eq"
        )
        #expect(result.value, "\(operation) rejected \(type)")
      }
    }

    for operation in ["readonly", "noaccess"] {
      let result: BooleanValue = try await Interpreter.result(
        content: "<<>> \(operation) type /dicttype eq"
      )
      #expect(result.value, "\(operation) rejected dicttype")
    }

    for operation in ["executeonly", "readonly", "noaccess", "rcheck", "wcheck"] {
      let result: BooleanValue = try await Interpreter.result(
        content: """
          {save \(operation)} stopped clear
          $error /errorname get /typecheck eq
          $error /command get /\(operation) load eq and
          """
      )
      #expect(result.value, "\(operation) accepted a save object")
    }

    let dictionaryResult: BooleanValue = try await Interpreter.result(
      content: """
        {<<>> executeonly} stopped clear
        $error /errorname get /typecheck eq
        $error /command get /executeonly load eq and
        """
    )
    #expect(dictionaryResult.value)
  }

  @Test
  func accessReductionIsIdempotentAndMonotonic() async throws {
    let validPrograms = [
      ("[] readonly readonly executeonly executeonly noaccess noaccess", false, false),
      ("0 packedarray readonly readonly executeonly executeonly noaccess noaccess", false, false),
      ("() readonly readonly executeonly executeonly noaccess noaccess", false, false),
      ("(%stdout) (w) file readonly readonly executeonly executeonly noaccess noaccess", false, false),
      ("<<>> readonly readonly", true, false),
      ("<<>> noaccess noaccess", false, false),
    ]

    for (program, readable, writable) in validPrograms {
      let result: BooleanValue = try await Interpreter.result(
        content: "\(program) dup rcheck \(readable) eq exch wcheck \(writable) eq and"
      )
      #expect(result.value, "Invalid final access for \(program)")
    }

    let invalidPrograms = [
      ("[] executeonly readonly", "readonly"),
      ("[] noaccess executeonly", "executeonly"),
      ("() noaccess readonly", "readonly"),
      ("<<>> readonly noaccess", "noaccess"),
    ]

    for (program, operation) in invalidPrograms {
      let result: BooleanValue = try await Interpreter.result(
        content: """
          {\(program)} stopped clear
          $error /errorname get /invalidaccess eq
          $error /command get /\(operation) load eq and
          """
      )
      #expect(result.value, "\(program) did not produce invalidaccess")
    }
  }

  @Test
  func accessChangesPreserveObjectAndDictionaryAliasingRules() async throws {
    let independentViewPrograms = [
      "[] dup readonly pop dup rcheck exch wcheck and",
      "() dup readonly pop dup rcheck exch wcheck and",
      "0 packedarray dup executeonly pop rcheck",
      "(%stdout) (w) file dup noaccess pop wcheck",
    ]

    for program in independentViewPrograms {
      let result: BooleanValue = try await Interpreter.result(content: program)
      #expect(result.value, "Access leaked to an alias in \(program)")
    }

    let readOnlyDictionary: BooleanValue = try await Interpreter.result(
      content: "<<>> dup readonly pop dup rcheck exch wcheck not and"
    )
    #expect(readOnlyDictionary.value)

    let noAccessDictionary: BooleanValue = try await Interpreter.result(
      content: "<<>> dup noaccess pop dup rcheck not exch wcheck not and"
    )
    #expect(noAccessDictionary.value)
  }

  @Test
  func testTestExecutableAttribute() async throws {
    let res1 = try await Interpreter.results(content: "(a) xcheck")
    expectEqual(res1.count, 1)
    expectEqual(try res1[0].value(as: BooleanValue.self).value, false)

    let res2 = try await Interpreter.results(content: "{} xcheck")
    expectEqual(res2.count, 1)
    expectEqual(try res2[0].value(as: BooleanValue.self).value, true)
  }

  @Test
  func testTestReadableAttribute() async throws {
    let res1 = try await Interpreter.results(content: "(a) rcheck")
    expectEqual(res1.count, 1)
    expectEqual(try res1[0].value(as: BooleanValue.self).value, true)

    let res2 = try await Interpreter.results(content: "{} rcheck")
    expectEqual(res2.count, 1)
    expectEqual(try res2[0].value(as: BooleanValue.self).value, true)

    let res3 = try await Interpreter.results(content: "{} noaccess rcheck")
    expectEqual(res3.count, 1)
    expectEqual(try res3[0].value(as: BooleanValue.self).value, false)

    do {
      _ = try await Interpreter.results(content: "false rcheck")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.typeCheck)
    }
  }

  @Test
  func testTestWritableAttribute() async throws {
    let res1 = try await Interpreter.results(content: "(a) wcheck")
    expectEqual(res1.count, 1)
    expectEqual(try res1[0].value(as: BooleanValue.self).value, true)

    let res2 = try await Interpreter.results(content: "{} wcheck")
    expectEqual(res2.count, 1)
    expectEqual(try res2[0].value(as: BooleanValue.self).value, true)

    do {
      _ = try await Interpreter.results(content: "false wcheck")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.typeCheck)
    }
  }

  @Test
  func accessChecksUseExactTypesAndEffectiveFileCapabilities() async throws {
    let cases = [
      ("[]", true, true),
      ("0 packedarray", true, false),
      ("<<>>", true, true),
      ("()", true, true),
      ("(%stdout) (w) file", false, true),
      ("(>) /ASCIIHexDecode filter", true, false),
    ]

    for (operand, readable, writable) in cases {
      let result: BooleanValue = try await Interpreter.result(
        content: """
          \(operand)
          dup rcheck \(readable) eq
          exch wcheck \(writable) eq and
          """
      )
      #expect(result.value, "Incorrect access capabilities for \(operand)")
    }
  }

  @Test
  func accessErrorsRetainOperandsAndCommandMetadata() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content: """
        {99 executeonly} stopped pop pop
        $error /errorname get /typecheck eq
        $error /command get /executeonly load eq and
        exch 99 eq and
        """
    )

    #expect(result.value)
  }

}
