//
//  PackedArrayTests.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct PackedArrayTests {

  @Test
  func testConstructLiteral() async throws {
    let arr1: PackedArrayValue = try await Interpreter.result(content: "1 (a) 3.0 false 4 packedarray")
    expectEqual(arr1.count, 4)
    expectEqual(try arr1.object(at: 0).value(as: IntegerValue.self).value, 1)
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 2).value(as: RealValue.self).value, 3.0)
    expectEqual(try arr1.object(at: 3).value(as: BooleanValue.self).value, false)
  }

  @Test
  func testConstructLiteralExecutingOperands() async throws {
    let arr1: PackedArrayValue = try await Interpreter.result(content: "1 2 add 1 packedarray")
    expectEqual(arr1.count, 1)
    expectEqual(try arr1.object(at: 0).value(as: IntegerValue.self).value, 3)
  }

  @Test
  func allocationModeControlsPackedArraysAndProcedures() async throws {
    let checks: [BooleanValue] = try await Interpreter.result(
      content:
        """
        true setglobal
        1 2 2 packedarray gcheck
        true setpacking
        {1 2 add} gcheck
        """,
      count: 2
    )

    #expect(checks.map { $0.value } == [true, true])

    let localChecks: [BooleanValue] = try await Interpreter.result(
      content: "1 1 packedarray gcheck true setpacking {1} gcheck",
      count: 2
    )

    #expect(localChecks.allSatisfy { !$0.value })
  }

  @Test
  func globalPackedArraysRejectLocalCompositeValues() async throws {
    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "/local (value) def true setglobal local 1 packedarray")
    }

    let localString = Object.string("local", access: .unlimited, vm: .local, kind: .literal)
    #expect(throws: Error.invalidAccess) {
      try PackedArrayValue(elements: [localString], vm: .global)
    }
  }

  @Test
  func bindPreservesProcedureVM() async throws {
    let local: BooleanValue = try await Interpreter.result(
      content: "true setpacking /p {1 2 add} def true setglobal /p load bind gcheck"
    )
    #expect(local.value == false)

    let global: BooleanValue = try await Interpreter.result(
      content: "true setglobal true setpacking /p {1 2 add} def /p load bind gcheck"
    )
    #expect(global.value == true)
  }

  @Test
  func testLength() async throws {
    let len: IntegerValue = try await Interpreter.result(content: "0 10 {1 add dup} repeat packedarray length")
    expectEqual(len.value, 10)
  }

  @Test
  func testGet() async throws {
    let int: IntegerValue = try await Interpreter.result(content: "true setpacking {1 2 3 4 5} 2 get")
    expectEqual(int.value, 3)
  }

  @Test
  func testPutFails() async throws {
    do {
      _ = try await Interpreter.execute(content: "true setpacking {1 2 3 4 5} dup 2 (abc) put")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectEqual(error, Error.typeCheck)
    }
  }

  @Test
  func testGetInterval() async throws {
    let results = try await Interpreter.results(
      content: "true setglobal (a) (b) (c) (d) (e) 5 packedarray cvx dup 1 3 getinterval"
    )
    #expect(results.count == 2)
    let interval = try results[0].value(as: PackedArrayValue.self)
    let source = try results[1].value(as: PackedArrayValue.self)
    expectEqual(interval.count, 3)
    expectEqual(interval.vm, .global)
    expectEqual(interval.access, .readOnly)
    expectEqual(results.first?.kind, .executable)
    expectEqual(try interval.object(at: 0).value(as: StringValue.self).string, "b")
    expectEqual(try interval.object(at: 1).value(as: StringValue.self).string, "c")
    expectEqual(try interval.object(at: 2).value(as: StringValue.self).string, "d")
    #expect(interval.allocation === source.allocation)
  }

  @Test
  func testPutInterval() async throws {
    let ps = "true setpacking {(a)(b)(c)(d)(e)} 1 {(f)(g)(h)} putinterval"
    do {
      _ = try await Interpreter.execute(content: ps)
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectEqual(error, Error.typeCheck)
    }
  }

  @Test
  func testArrayStore() async throws {
    do {
      _ = try await Interpreter.execute(content: "(a) (bcd) (ef) 3 packedarray astore")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectEqual(error, Error.typeCheck)
    }
  }

  @Test
  func testArrayLoad() async throws {
    let ops = try await Interpreter.results(content: "true setpacking {23 (ab) -6} aload")
    expectEqual(ops.count, 4)
    expectEqual((ops[0].value as? PackedArrayValue)?.count, 3)
    expectEqual((ops[1].value as? IntegerValue)?.value, -6)
    expectEqual((ops[2].value as? StringValue)?.string, "ab")
    expectEqual((ops[3].value as? IntegerValue)?.value, 23)
  }

  @Test
  func testCopy() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "true setpacking {1 (a) 3.0 //false} 5 array copy")
    expectEqual(arr1.count, 4)
    expectEqual(try arr1.object(at: 0).value(as: IntegerValue.self).value, 1)
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 2).value(as: RealValue.self).value, 3.0)
    expectEqual(try arr1.object(at: 3).value(as: BooleanValue.self).value, false)
  }

  @Test
  func testForAll() async throws {
    let int: IntegerValue = try await Interpreter.result(content: "true setpacking 0 {13 29 3 -8 21} {add} forall")
    expectEqual(int.value, 58)
  }

}
