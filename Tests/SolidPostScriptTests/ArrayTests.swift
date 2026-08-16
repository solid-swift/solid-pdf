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
    let arr2: ArrayValue = try await Interpreter.result(content: "[(a)(b)(c)(d)(e)] 1 3 getinterval")
    expectEqual(arr2.count, 3)
    expectEqual(try arr2.object(at: 0).value(as: StringValue.self).string, "b")
    expectEqual(try arr2.object(at: 1).value(as: StringValue.self).string, "c")
    expectEqual(try arr2.object(at: 2).value(as: StringValue.self).string, "d")
  }

  @Test
  func testGetIntervalOfInterval() async throws {
    let arr3: ArrayValue = try await Interpreter.result(content: "[(a)(b)(c)(d)(e)] 1 4 getinterval 1 2 getinterval")
    expectEqual(arr3.count, 2)
    expectEqual(try arr3.object(at: 0).value(as: StringValue.self).string, "c")
    expectEqual(try arr3.object(at: 1).value(as: StringValue.self).string, "d")
  }

  @Test
  func testGetIntervalSharesElements() async throws {
    let (interval, array) = try await Interpreter.result(
      content: "/a [1 2 3 4 5] def /i a 1 3 getinterval def i 1 30 put a i",
      as: (ArrayValue, ArrayValue).self
    )
    expectEqual(try interval.object(at: 1).value(as: IntegerValue.self).value, 30)
    expectEqual(try array.object(at: 2).value(as: IntegerValue.self).value, 30)
  }

  @Test
  func uncheckedTraversalUsesOnlyTheSelectedInterval() throws {
    let array = try ArrayValue(elements: [1, 2, 3, 4, 5], access: .unlimited, vm: .local)
    let interval = try ArrayValue(sharing: array, subRange: 1..<4)
    var values: [Int32] = []

    try interval.forEachUnchecked {
      values.append(try $0.value(as: IntegerValue.self).value)
    }

    #expect(values == [2, 3, 4])
  }

  @Test
  func arrayEqualityAndHashingUseTheSharedValueAndSelectedRange() throws {
    let array = try ArrayValue(elements: [1, 2, 3], access: .unlimited, vm: .local)
    let fullInterval = try ArrayValue(sharing: array, subRange: 0..<3)
    let firstInterval = try ArrayValue(sharing: array, subRange: 0..<2)
    let sameFirstInterval = try ArrayValue(sharing: array, subRange: 0..<2)
    let secondInterval = try ArrayValue(sharing: array, subRange: 1..<3)
    let distinct = try ArrayValue(elements: [1, 2, 3], access: .unlimited, vm: .local)
    let empty = try ArrayValue(elements: [], access: .unlimited, vm: .local)
    let distinctEmpty = try ArrayValue(elements: [], access: .unlimited, vm: .local)
    var restrictedInterval = firstInterval
    try restrictedInterval.setAccess(to: .readOnly)

    #expect(Object(value: array) == Object(value: fullInterval))
    #expect(Object(value: firstInterval) == Object(value: sameFirstInterval))
    #expect(Object(value: array) != Object(value: firstInterval))
    #expect(Object(value: firstInterval) != Object(value: secondInterval))
    #expect(Object(value: array) != Object(value: distinct))
    #expect(Object(value: empty) == Object(value: distinctEmpty))
    #expect(
      Object(value: firstInterval, kind: .literal) == Object(value: restrictedInterval, kind: .executable)
    )
    #expect(Set([Object(value: firstInterval), Object(value: sameFirstInterval)]).count == 1)
    #expect(Set([Object(value: firstInterval), Object(value: secondInterval)]).count == 2)
    #expect(Set([Object(value: empty), Object(value: distinctEmpty)]).count == 1)
  }

  @Test
  func packedArrayEqualityAndHashingUseTheSharedValueAndSelectedRange() throws {
    let array = try PackedArrayValue(elements: [1, 2, 3], vm: .local)
    let fullInterval = try PackedArrayValue(sharing: array, subRange: 0..<3)
    let firstInterval = try PackedArrayValue(sharing: array, subRange: 0..<2)
    let sameFirstInterval = try PackedArrayValue(sharing: array, subRange: 0..<2)
    let secondInterval = try PackedArrayValue(sharing: array, subRange: 1..<3)
    let distinct = try PackedArrayValue(elements: [1, 2, 3], vm: .local)
    let empty = try PackedArrayValue(elements: [], vm: .local)
    let distinctEmpty = try PackedArrayValue(elements: [], vm: .local)
    let ordinaryEmpty = try ArrayValue(elements: [], access: .unlimited, vm: .local)

    #expect(Object(value: array) == Object(value: fullInterval))
    #expect(Object(value: firstInterval) == Object(value: sameFirstInterval))
    #expect(Object(value: array) != Object(value: firstInterval))
    #expect(Object(value: firstInterval) != Object(value: secondInterval))
    #expect(Object(value: array) != Object(value: distinct))
    #expect(Object(value: empty) == Object(value: distinctEmpty))
    #expect(Set([Object(value: firstInterval), Object(value: sameFirstInterval)]).count == 1)
    #expect(Set([Object(value: firstInterval), Object(value: secondInterval)]).count == 2)
    #expect(Set([Object(value: empty), Object(value: distinctEmpty)]).count == 1)
    #expect(Object(value: empty) != Object(value: ordinaryEmpty))
  }

  @Test
  func testPutInterval() async throws {
    let arr1: ArrayValue = try await Interpreter.result(content: "[(a)(b)(c)(d)(e)] dup 1 [(f)(g)(h)] putinterval")
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
      content: "/a [(a)(b)(c)(d)(e)] def /i a 1 4 getinterval def i 1 [(f)(g)] putinterval a i",
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
  func testOverlappingPutInterval() async throws {
    let array: ArrayValue = try await Interpreter.result(
      content: "/a [1 2 3 4 5] def a 1 a 0 4 getinterval putinterval a"
    )
    let values = try (0..<array.count).map { try array.object(at: $0).value(as: IntegerValue.self).value }
    #expect(values == [1, 1, 2, 3, 4])
  }

  @Test
  func getIntervalErrorRestoresOperandsForStopped() async throws {
    let results = try await Interpreter.results(content: "{ [1] 2 1 getinterval } stopped")
    #expect(results.count == 5)
    #expect(try results[0].value(as: BooleanValue.self).value)
    #expect(results[1].value is Operators.GetInterval)
    #expect(try results[2].value(as: IntegerValue.self).value == 1)
    #expect(try results[3].value(as: IntegerValue.self).value == 2)
    #expect(results[4].value is ArrayValue)
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

  @Test
  func forallEnumeratesOnlyTheSelectedInterval() async throws {
    let int: IntegerValue = try await Interpreter.result(content: "0 [10 1 2 20] 1 2 getinterval {add} forall")
    #expect(int.value == 3)
  }

}
