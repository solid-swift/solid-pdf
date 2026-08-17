//
//  UserObjectsTests.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct UserObjectsTests {

  @Test
  func definitionPreservesGrowthAndExistingObjects() async throws {
    let first: ArrayValue = try await Interpreter.result(
      content: "17 (abc) defineuserobject UserObjects"
    )
    #expect(first.count == 50)
    #expect(try first.object(at: 17).value(as: StringValue.self).string == "abc")

    let doubled: ArrayValue = try await Interpreter.result(
      content: "27 (abc) defineuserobject UserObjects"
    )
    #expect(doubled.count == 54)

    let expanded: ArrayValue = try await Interpreter.result(
      content: "0 (old) defineuserobject 50 (new) defineuserobject UserObjects"
    )
    #expect(expanded.count == 100)
    #expect(try expanded.object(at: 0).value(as: StringValue.self).string == "old")
    #expect(try expanded.object(at: 50).value(as: StringValue.self).string == "new")
  }

  @Test(
    arguments: [
      "0 { 40 2 add } defineuserobject 0 execuserobject",
      "true setpacking /p { 40 2 add } def false setpacking 0 /p load defineuserobject 0 execuserobject",
      "/fortytwo 42 def 0 /fortytwo cvx defineuserobject 0 execuserobject",
      "0 /add load defineuserobject 20 22 0 execuserobject",
      "0 (40 2 add) cvx defineuserobject 0 execuserobject",
    ]
  )
  func executableUserObjectsExecute(program: String) async throws {
    let result: IntegerValue = try await Interpreter.result(content: program)
    #expect(result.value == 42)
  }

  @Test
  func literalAndUndefinedUserObjectsArePushed() async throws {
    let procedure = try await Interpreter.results(
      content: "0 { 1 2 add } cvlit defineuserobject 0 execuserobject"
    )
    let literalProcedure = try #require(procedure.first)
    #expect(literalProcedure.kind == .literal)
    #expect(literalProcedure.value is ArrayValue)

    let literal: StringValue = try await Interpreter.result(
      content: "0 (abc) defineuserobject 0 execuserobject"
    )
    #expect(literal.string == "abc")

    let undefined = try await Interpreter.results(
      content: "17 (abc) defineuserobject 16 execuserobject"
    )
    #expect(undefined.first?.value is NullValue)
  }

  @Test
  func executionEnforcesAccessAndStackLimits() async throws {
    let accessError: NameValue = try await Interpreter.result(
      content: """
        0 { 1 } noaccess defineuserobject
        { 0 execuserobject } stopped clear
        $error /errorname get
        """
    )
    #expect(accessError.value == "invalidaccess")

    let stackError: NameValue = try await Interpreter.result(
      content: """
        /recurse { 0 execuserobject } def
        0 /recurse load defineuserobject
        << /MaxExecStack 2 >> setuserparams
        { 0 execuserobject } stopped clear
        $error /errorname get
        """
    )
    #expect(stackError.value == "execstackoverflow")
  }

  @Test
  func executedProcedureErrorsRetainTheirFailingCommand() async throws {
    let command: NameValue = try await Interpreter.result(
      content: """
        0 { doesnotexist } defineuserobject
        { 0 execuserobject } stopped clear
        $error /command get
        """
    )
    #expect(command.value == "doesnotexist")
  }

  @Test
  func operatorsIgnoreShadowingUserObjectsEntries() async throws {
    let (value, shadowLength): (StringValue, IntegerValue) = try await Interpreter.result(
      content: """
        17 (first) defineuserobject
        1 dict begin
          /UserObjects 1 array def
          50 (second) defineuserobject
          UserObjects length
        end
        userdict /UserObjects get 50 get
        """
    )
    #expect(value.string == "second")
    #expect(shadowLength.value == 1)
  }

  @Test
  func invalidIndicesFailBeforeCreatingUserObjects() async throws {
    for (index, expectedError) in [
      ("-1", "rangecheck"),
      ("2147483647", "limitcheck"),
    ] {
      let (errorName, commandMatches, userObjectsKnown): (NameValue, BooleanValue, BooleanValue) =
        try await Interpreter.result(
          content: """
            { \(index) null defineuserobject } stopped clear
            userdict /UserObjects known
            $error /command get /defineuserobject load eq
            $error /errorname get
            """
        )
      #expect(errorName.value == expectedError)
      #expect(commandMatches.value)
      #expect(!userObjectsKnown.value)
    }
  }

  @Test
  func allocationFailureIsAtomicAndUsesLocalVMLimit() async throws {
    let (errorName, commandMatches, userObjectsKnown): (NameValue, BooleanValue, BooleanValue) =
      try await Interpreter.result(
        content: """
          /allocate { 100 null defineuserobject } def
          << /MaxLocalVM 1 >> setuserparams
          /allocate load stopped clear
          userdict /UserObjects known
          $error /command get /defineuserobject load eq
          $error /errorname get
          """
      )
    #expect(errorName.value == "VMerror")
    #expect(commandMatches.value)
    #expect(!userObjectsKnown.value)
  }

  @Test
  func failedExpansionRestoresOperandsExactly() async throws {
    let results = try await Interpreter.results(
      content: "{ 2147483647 null defineuserobject } stopped"
    )

    #expect(results.count == 4)
    #expect(try results[0].value(as: BooleanValue.self).value)
    #expect(results[1].value is Operators.DefineUserObject)
    #expect(results[2].value is NullValue)
    #expect(try results[3].value(as: IntegerValue.self).value == .max)
  }

  @Test
  func tableIsAlwaysLocalWithoutChangingAllocationMode() async throws {
    let values: [BooleanValue] = try await Interpreter.result(
      content: "true setglobal 17 (abc) defineuserobject UserObjects gcheck currentglobal",
      count: 2
    )
    #expect(values.map(\.value) == [true, false])
  }

  @Test
  func saveRestoreRevertsExpansion() async throws {
    let (value, length): (StringValue, IntegerValue) = try await Interpreter.result(
      content: """
        0 (old) defineuserobject
        /saved save def
        50 (new) defineuserobject
        saved restore
        UserObjects length
        UserObjects 0 get
        """
    )
    #expect(value.string == "old")
    #expect(length.value == 50)
  }

  @Test
  func undefineReplacesEntriesWithNullAndAbsentTableIsAllowed() async throws {
    let result: ArrayValue = try await Interpreter.result(
      content: "1 1 defineuserobject 1 undefineuserobject UserObjects"
    )
    #expect(result.count == 50)
    #expect(try result.object(at: 1).value is NullValue)

    let context = try await Interpreter.execute(content: "17 undefineuserobject")
    #expect(try await context.results().isEmpty)
  }

  @Test
  func lookupFailuresRetainExistingErrors() async throws {
    await #expect(throws: Error.undefined) {
      try await Interpreter.execute(content: "17 execuserobject")
    }
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "17 (abc) defineuserobject 100 execuserobject")
    }
  }

  @Test
  func contextsKeepUserObjectsIsolated() async throws {
    async let first: StringValue = Interpreter.result(
      content: "0 (first) defineuserobject 0 execuserobject"
    )
    async let second: StringValue = Interpreter.result(
      content: "0 (second) defineuserobject 0 execuserobject"
    )

    let (firstValue, secondValue) = try await (first, second)
    #expect(firstValue.string == "first")
    #expect(secondValue.string == "second")
  }
}
