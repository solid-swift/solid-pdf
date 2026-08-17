//
//  ProcedureTests.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct ProcedureTests {

  @Test
  func testConstructDeferred() async throws {
    let proc: CollectionValue = try await Interpreter.result(content: "{10 add}")
    expectEqual(proc.count, 2)
  }

  @Test
  func tokenConstructsNestedProcedureAsOneObject() async throws {
    let results = try await Interpreter.results(content: "({1 {2} 3} tail) token")

    #expect(try results[0].value(as: BooleanValue.self).value)
    let procedure = try results[1].value(as: ArrayValue.self)
    #expect(results[1].kind == .executable)
    #expect(procedure.count == 3)
    #expect(try procedure.object(at: 0).value(as: IntegerValue.self).value == 1)
    let nested = try procedure.object(at: 1).value(as: ArrayValue.self)
    #expect(try nested.object(at: 0).value(as: IntegerValue.self).value == 2)
    #expect(try procedure.object(at: 2).value(as: IntegerValue.self).value == 3)
    #expect(try results[2].value(as: StringValue.self).string == " tail")
  }

  @Test
  func procedureScanningHonorsPackingAllocationAndImmediateNames() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /value 42 def
        true setglobal true setpacking ({ //value }) token
        """
    )

    #expect(try results[0].value(as: BooleanValue.self).value)
    let procedure = try results[1].value(as: PackedArrayValue.self)
    #expect(procedure.vm == .global)
    #expect(try procedure.object(at: 0).value(as: IntegerValue.self).value == 42)
  }

  @Test
  func braceDelimitersAreNotSystemDictionaryOperators() async throws {
    let results: [BooleanValue] = try await Interpreter.result(
      content: "systemdict ({) cvn known systemdict (}) cvn known",
      count: 2
    )
    #expect(results.allSatisfy { !$0.value })
  }

  @Test
  func malformedProceduresRaiseSyntaxErrorWithoutLeakingConstructionState() async throws {
    for program in ["{1", "}", ")", ">", "~>", "({1) token", "(}) token"] {
      do {
        _ = try await Interpreter.execute(content: program)
        Issue.record("Expected syntaxerror for \(program)")
      } catch let error as Error {
        #expect(error == .syntaxError, "Unexpected error for \(program)")
      }
    }

    let results = try await Interpreter.results(content: "99 ({1) cvx stopped count")
    #expect(try results[0].value(as: IntegerValue.self).value == 3)
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: StringValue.self).string == "{1")
    #expect(try results[3].value(as: IntegerValue.self).value == 99)
  }

  @Test
  func tokenAttributesMalformedProcedureToToken() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content: "({1) { token } stopped clear $error /command get /token load eq"
    )
    #expect(result.value)
  }

  @Test
  func testBind() async throws {
    let proc: CollectionValue = try await Interpreter.result(content: "{10 20 add} bind")
    guard proc.count == 3 else {
      return recordIssue("Expected 3 elements in procedure")
    }
    expectEqual(try proc.object(at: 0).value(as: IntegerValue.self).value, 10)
    expectEqual(try proc.object(at: 1).value(as: IntegerValue.self).value, 20)
    expectEqual(try proc.object(at: 2).value(as: Operators.Add.self), .instance)
  }

  @Test
  func testBindNested() async throws {
    let proc: CollectionValue = try await Interpreter.result(content: "{10 10 {0 {add}} 2 repeat} bind")
    guard proc.count == 5 else {
      return recordIssue("Expected 3 elements in procedure")
    }
    expectEqual(try proc.object(at: 0).value(as: IntegerValue.self).value, 10)
    expectEqual(try proc.object(at: 1).value(as: IntegerValue.self).value, 10)
    expectEqual(try proc.object(at: 3).value(as: IntegerValue.self).value, 2)
    expectEqual(try proc.object(at: 4).value(as: Operators.Repeat.self), .instance)

    let nest1 = try proc.object(at: 2).value(as: CollectionValue.self)
    guard nest1.count == 2 else {
      return recordIssue("Expected 2 elements in nested procedure")
    }
    expectEqual(try nest1.object(at: 0).value(as: IntegerValue.self).value, 0)

    let nest2 = try nest1.object(at: 1).value(as: CollectionValue.self)
    guard nest2.count == 1 else {
      return recordIssue("Expected 1 elements in nested procedure")
    }
    expectEqual(try nest2.object(at: 0).value(as: Operators.Add.self), .instance)
  }

}
