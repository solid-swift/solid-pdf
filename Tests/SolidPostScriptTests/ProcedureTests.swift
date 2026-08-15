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
