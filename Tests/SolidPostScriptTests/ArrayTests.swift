//
//  ArrayTests.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct ArrayTests {

  @Test
  func testCreate() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "10 array")
    expectEqual(arr1.count, 10)
    expectEqual(try arr1.object(at: 0).value(as: NullValue.self), .instance)
  }

  @Test
  func testConstructLiteral() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "[ 1 (a) 3.0 false]")
    expectEqual(arr1.count, 4)
    expectEqual(try arr1.object(at: 0).value(as: IntegerValue.self).value, 1)
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 2).value(as: RealValue.self).value, 3.0)
    expectEqual(try arr1.object(at: 3).value(as: BooleanValue.self).value, false)
  }

  @Test
  func testConstructLiteralExecutingOperands() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "[1 2 add]")
    expectEqual(arr1.count, 1)
    expectEqual(try arr1.object(at: 0).value(as: IntegerValue.self).value, 3)
  }

  @Test
  func testLength() async throws {
    let len: IntegerValue = try await Interpreter.result(content: "10 array length")
    expectEqual(len.value, 10)
  }

  @Test
  func testGet() async throws {
    let int: IntegerValue = try await Interpreter.result(content: "[1 2 3 4 5] 2 get")
    expectEqual(int.value, 3)
  }

  @Test
  func testPut() async throws {
    let array: ArrayValue = try await Interpreter.result(content: "[1 2 3 4 5] dup 2 (abc) put")
    expectEqual(try array.object(at: 0).value(as: IntegerValue.self).value, 1)
    expectEqual(try array.object(at: 1).value(as: IntegerValue.self).value, 2)
    expectEqual(try array.object(at: 2).value(as: StringValue.self).string, "abc")
    expectEqual(try array.object(at: 3).value(as: IntegerValue.self).value, 4)
    expectEqual(try array.object(at: 4).value(as: IntegerValue.self).value, 5)
  }

  @Test
  func testGetInterval() async throws {
    let (arr2, arr1) = try await Interpreter.result(
      content: "[(a)(b)(c)(d)(e)] 1 3 getinterval",
      as: (ArrayValue, ArrayValue).self
    )
    expectEqual(arr2.count, 3)
    expectEqual(try arr2.object(at: 0).value(as: StringValue.self).string, "b")
    expectEqual(try arr2.object(at: 1).value(as: StringValue.self).string, "c")
    expectEqual(try arr2.object(at: 2).value(as: StringValue.self).string, "d")
    expectEqual(arr1.count, 5)
    expectEqual(try arr1.object(at: 0).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "b")
    expectEqual(try arr1.object(at: 2).value(as: StringValue.self).string, "c")
    expectEqual(try arr1.object(at: 3).value(as: StringValue.self).string, "d")
    expectEqual(try arr1.object(at: 4).value(as: StringValue.self).string, "e")
  }

  @Test
  func testGetIntervalOfInterval() async throws {
    let (arr3, arr2, arr1) = try await Interpreter.result(
      content: "[(a)(b)(c)(d)(e)] 1 4 getinterval 1 2 getinterval",
      as: (ArrayValue, ArrayValue, ArrayValue).self
    )
    expectEqual(arr3.count, 2)
    expectEqual(try arr3.object(at: 0).value(as: StringValue.self).string, "c")
    expectEqual(try arr3.object(at: 1).value(as: StringValue.self).string, "d")
    expectEqual(arr2.count, 4)
    expectEqual(try arr2.object(at: 0).value(as: StringValue.self).string, "b")
    expectEqual(try arr2.object(at: 1).value(as: StringValue.self).string, "c")
    expectEqual(try arr2.object(at: 2).value(as: StringValue.self).string, "d")
    expectEqual(try arr2.object(at: 3).value(as: StringValue.self).string, "e")
    expectEqual(arr1.count, 5)
    expectEqual(try arr1.object(at: 0).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "b")
    expectEqual(try arr1.object(at: 2).value(as: StringValue.self).string, "c")
    expectEqual(try arr1.object(at: 3).value(as: StringValue.self).string, "d")
    expectEqual(try arr1.object(at: 4).value(as: StringValue.self).string, "e")
  }

  @Test
  func testPutInterval() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "[(a)(b)(c)(d)(e)] 1 [(f)(g)(h)] putinterval")
    expectEqual(arr1.count, 5)
    expectEqual(try arr1.object(at: 0).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "f")
    expectEqual(try arr1.object(at: 2).value(as: StringValue.self).string, "g")
    expectEqual(try arr1.object(at: 3).value(as: StringValue.self).string, "h")
    expectEqual(try arr1.object(at: 4).value(as: StringValue.self).string, "e")
  }

  @Test
  func testPutIntervalToInterval() async throws {
    let (arr2, arr1) = try await Interpreter.result(
      content: "[(a)(b)(c)(d)(e)] 1 4 getinterval 1 [(f)(g)] putinterval",
      as: (ArrayValue, ArrayValue).self
    )
    expectEqual(arr2.count, 4)
    expectEqual(try arr2.object(at: 0).value(as: StringValue.self).string, "b")
    expectEqual(try arr2.object(at: 1).value(as: StringValue.self).string, "f")
    expectEqual(try arr2.object(at: 2).value(as: StringValue.self).string, "g")
    expectEqual(try arr2.object(at: 3).value(as: StringValue.self).string, "e")
    expectEqual(arr1.count, 5)
    expectEqual(try arr1.object(at: 0).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "b")
    expectEqual(try arr1.object(at: 2).value(as: StringValue.self).string, "f")
    expectEqual(try arr1.object(at: 3).value(as: StringValue.self).string, "g")
    expectEqual(try arr1.object(at: 4).value(as: StringValue.self).string, "e")
  }

  @Test
  func testArrayStore() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "(a) (bcd) (ef) 3 array astore")
    expectEqual(arr1.count, 3)
    expectEqual(try arr1.object(at: 0).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "bcd")
    expectEqual(try arr1.object(at: 2).value(as: StringValue.self).string, "ef")
  }

  @Test
  func testArrayLoad() async throws {
    let ops = try await Interpreter.results(content: "[23 (ab) -6] aload")
    expectEqual(ops.count, 4)
    expectEqual((ops[0].value as? ArrayValue)?.count, 3)
    expectEqual((ops[1].value as? IntegerValue)?.value, -6)
    expectEqual((ops[2].value as? StringValue)?.string, "ab")
    expectEqual((ops[3].value as? IntegerValue)?.value, 23)
  }

  @Test
  func testCopy() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "[ 1 (a) 3.0 false] 5 array copy")
    expectEqual(arr1.count, 4)
    expectEqual(try arr1.object(at: 0).value(as: IntegerValue.self).value, 1)
    expectEqual(try arr1.object(at: 1).value(as: StringValue.self).string, "a")
    expectEqual(try arr1.object(at: 2).value(as: RealValue.self).value, 3.0)
    expectEqual(try arr1.object(at: 3).value(as: BooleanValue.self).value, false)
  }

  @Test
  func testForAll() async throws {
    let int: IntegerValue = try await Interpreter.result(content: "0 [13 29 3 -8 21] {add} forall")
    expectEqual(int.value, 58)
  }

}
