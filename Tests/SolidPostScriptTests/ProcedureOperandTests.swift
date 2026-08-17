//
//  ProcedureOperandTests.swift
//

import Foundation
@testable import SolidPostScript
import Testing

private let invalidProcedureSources = [
  "7",
  "() cvx",
  "/noop cvx",
  "/pop load",
  "[]",
  "true setpacking {} cvlit false setpacking",
]

private let unexecutedProcedurePrograms = [
  "42 false {} noaccess if",
  "42 true {} {} noaccess ifelse",
  "42 1 1 0 {} noaccess for",
  "42 0 {} noaccess repeat",
  "42 [] {} noaccess forall",
  "42 (__solidpdf_no_match__) {} noaccess 64 string /ProcSet resourceforall",
]

private enum ProcedureOperatorCase: String, CaseIterable, Sendable {
  case ifOperator = "if"
  case ifElse = "ifelse"
  case forOperator = "for"
  case `repeat`
  case loop
  case forAll = "forall"
  case resourceForAll = "resourceforall"

  func program(with procedure: String) -> String {
    switch self {
    case .ifOperator:
      "false \(procedure) if"
    case .ifElse:
      "true {} \(procedure) ifelse"
    case .forOperator:
      "1 1 0 \(procedure) for"
    case .repeat:
      "0 \(procedure) repeat"
    case .loop:
      "\(procedure) loop"
    case .forAll:
      "[] \(procedure) forall"
    case .resourceForAll:
      "(__solidpdf_no_match__) \(procedure) 64 string /ProcSet resourceforall"
    }
  }
}

@Suite
struct ProcedureOperandTests {

  @Test(arguments: invalidProcedureSources)
  func procedureOperatorsRejectNonProcedures(_ invalidProcedure: String) async throws {
    for operatorCase in ProcedureOperatorCase.allCases {
      let (errorName, commandMatches): (NameValue, BooleanValue) = try await Interpreter.result(
        content:
          """
          { \(operatorCase.program(with: invalidProcedure)) } stopped clear
          $error /command get /\(operatorCase.rawValue) load eq
          $error /errorname get
          """
      )

      #expect(errorName.value == "typecheck", "Expected \(operatorCase.rawValue) to reject \(invalidProcedure)")
      #expect(commandMatches.value, "Expected command attribution to remain \(operatorCase.rawValue)")
    }
  }

  @Test(arguments: unexecutedProcedurePrograms)
  func unexecutedProceduresAreNotAccessChecked(_ program: String) async throws {
    let result: IntegerValue = try await Interpreter.result(content: program)
    #expect(result.value == 42)
  }

  @Test
  func packedProceduresExecuteAcrossControlAndCollectionOperators() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        /count 0 def
        true setpacking
        true { /count count 1 add store } if
        true { /count count 1 add store } {} ifelse
        1 1 1 { pop /count count 1 add store } for
        1 { /count count 1 add store } repeat
        { /count count 1 add store exit } loop
        [1] { pop /count count 1 add store } forall
        false setpacking
        count
        """
    )

    #expect(result.value == 6)
  }

  @Test
  func resourceForAllAcceptsPackedProcedures() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        /ProcedureOperandTest <<>> /ProcSet defineresource pop
        /count 0 def
        true setpacking
        (ProcedureOperandTest) { pop /count count 1 add store } 64 string /ProcSet resourceforall
        false setpacking
        count
        """
    )

    #expect(result.value == 1)
  }

  @Test
  func selectedNoAccessProceduresRaiseInvalidAccess() async throws {
    let ordinary: NameValue = try await Interpreter.result(
      content:
        """
        { true {} noaccess if } stopped clear
        $error /errorname get
        """
    )
    #expect(ordinary.value == "invalidaccess")

    let packed: NameValue = try await Interpreter.result(
      content:
        """
        true setpacking /procedure {} noaccess def false setpacking
        { true /procedure load if } stopped clear
        $error /errorname get
        """
    )
    #expect(packed.value == "invalidaccess")
  }

  @Test
  func execAndStoppedContinueAcceptingArbitraryObjects() async throws {
    let results = try await Interpreter.results(content: "7 exec 8 stopped")

    #expect(results.count == 3)
    #expect(try results[0].value(as: BooleanValue.self).value == false)
    #expect(try results[1].value(as: IntegerValue.self).value == 8)
    #expect(try results[2].value(as: IntegerValue.self).value == 7)
  }

  @Test
  func procedureExecutionRetainsExecutionStackLimits() async throws {
    let errorName: NameValue = try await Interpreter.result(
      content:
        """
        /recurse { true /recurse load if } def
        << /MaxExecStack 2 >> setuserparams
        /recurse load stopped clear
        $error /errorname get
        """
    )

    #expect(errorName.value == "execstackoverflow")
  }

  @Test
  func typeCheckRestoresOperandsExactly() async throws {
    let results = try await Interpreter.results(content: "{ true 7 if } stopped")

    #expect(results.count == 4)
    #expect(try results[0].value(as: BooleanValue.self).value)
    #expect(results[1].value is Operators.If)
    #expect(try results[2].value(as: IntegerValue.self).value == 7)
    #expect(try results[3].value(as: BooleanValue.self).value)
  }

  @Test
  func resourceForAllValidationRestoresItsInternalDictionary() async throws {
    let (errorName, commandMatches, dictionaryDepthMatches): (NameValue, BooleanValue, BooleanValue) =
      try await Interpreter.result(
        content:
          """
          /before countdictstack def
          { (__solidpdf_no_match__) 7 64 string /ProcSet resourceforall } stopped clear
          countdictstack before eq
          $error /command get /resourceforall load eq
          $error /errorname get
          """
      )

    #expect(errorName.value == "typecheck")
    #expect(commandMatches.value)
    #expect(dictionaryDepthMatches.value)
  }

  @Test
  func resourceForAllCallbackErrorsPreserveCallbackDictionaryEffects() async throws {
    let (command, dictionaryGrowth): (NameValue, IntegerValue) = try await Interpreter.result(
      content:
        """
        /ProcedureOperandCallback <<>> /ProcSet defineresource pop
        /before countdictstack def
        { (ProcedureOperandCallback) { pop 1 dict begin doesnotexist } 64 string /ProcSet resourceforall }
          stopped pop
        countdictstack before sub
        $error /command get
        end
        """
    )

    #expect(command.value == "doesnotexist")
    #expect(dictionaryGrowth.value == 1)
  }
}
