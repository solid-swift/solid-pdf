//
//  DictionaryTests.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct DictionaryTests {

  @Test
  func testCreate() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "10 dict")
    expectGreaterThanOrEqual(dict1.capacity, 10)
  }

  @Test
  func testConstructLiteral() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "<< /a 1 /b 2 >>")
    expectEqual(try dict1.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 1)
    expectEqual(try dict1.objectValue(forKeyIfExists: "b", as: IntegerValue.self)?.value, 2)
  }

  @Test
  func testConstructLiteralExecutingOperands() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "<< /a 1 /b 2 3 add >>")
    expectEqual(try dict1.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 1)
    expectEqual(try dict1.objectValue(forKeyIfExists: "b", as: IntegerValue.self)?.value, 5)
  }

  @Test
  func testLength() async throws {
    let len1: IntegerValue = try await Interpreter.result(content: "10 dict length")
    expectEqual(len1.value, 0)

    let len2: IntegerValue = try await Interpreter.result(content: "<</a 1>> length")
    expectEqual(len2.value, 1)
  }

  @Test
  func testMaxLength() async throws {
    let (len1, dict1) = try await Interpreter.result(
      content: "10 dict maxlength",
      as: (IntegerValue, DictionaryValue).self
    )
    expectGreaterThanOrEqual(len1.value, 10)
    expectEqual(dict1.count, 0)
  }

  @Test
  func testBegin() async throws {
    let ctx = try await Interpreter.execute(content: "10 dict begin")
    let dict1 = try await ctx.currentDictionary()
    expectGreaterThanOrEqual(dict1.capacity, 10)
  }

  @Test
  func testEnd() async throws {
    let ctx = try await Interpreter.execute(content: "10 dict begin end")
    let depth = await ctx.dictionaryStackDepth
    expectEqual(depth, 3)
  }

  @Test
  func testDefine() async throws {
    let ctx1 = try await Interpreter.execute(content: "10 dict begin /a 1 def")
    let dict1 = try await ctx1.currentDictionary()
    expectEqual(try dict1.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 1)

    let ctx2 = try await Interpreter.execute(content: "10 dict begin /a 1 def /a a 10 mul def")
    let dict2 = try await ctx2.currentDictionary()
    expectEqual(try dict2.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 10)
  }

  @Test
  func testLoad() async throws {
    let int1: IntegerValue = try await Interpreter.result(content: "/num 123 def /num load")
    expectEqual(int1.value, 123)

    let proc1: CollectionValue = try await Interpreter.result(content: "/avg {add 2 div} def /avg load")
    expectEqual(proc1.count, 3)
  }

  @Test
  func testStore() async throws {
    let ctx1 = try await Interpreter.execute(content: "/a 123 store")
    let dict1 = try await ctx1.currentDictionary()
    expectEqual(try dict1.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 123)

    let ctx2 = try await Interpreter.execute(content: "/a 123 store 10 dict begin /a 456 store")
    let dict2 = try await ctx2.popDictionary().value(as: DictionaryValue.self)
    expectNil(try dict2.objectValue(forKeyIfExists: "a"))
    let dict3 = try await ctx2.currentDictionary()
    expectEqual(try dict3.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 456)
  }

  @Test
  func testGet() async throws {
    let int1: IntegerValue = try await Interpreter.result(content: "/a 123 def currentdict /a get")
    expectEqual(int1.value, 123)
  }

  @Test
  func testPut() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "10 dict dup /a 123 put")
    expectEqual(try dict1.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 123)
  }

  @Test
  func testUndefine() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "<< /a 123 /b 456 >> dup /a undef")
    expectNil(try dict1.objectValue(forKeyIfExists: "a"))
    expectEqual(try dict1.objectValue(forKeyIfExists: "b", as: IntegerValue.self)?.value, 456)
  }

  @Test
  func testKnown() async throws {
    let bool1: BooleanValue = try await Interpreter.result(content: "<< /a 123 /b 456 >> /a known")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "<< /a 123 /b 456 >> /d known")
    expectEqual(bool2.value, false)
  }

  @Test
  func testWhere() async throws {
    let ops1 = try await Interpreter.results(content: "<< /a 123 /b 456 >> begin /a where")
    expectEqual(ops1.count, 2)
    let bool1 = try requireValue(ops1[0].value as? BooleanValue, "Expected BooleanValue")
    expectEqual(bool1.value, true)
    let dict1 = try requireValue(ops1[1].value as? DictionaryValue, "Expected DictionaryValue")
    expectEqual(dict1.count, 2)
    expectEqual(try dict1.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 123)
    expectEqual(try dict1.objectValue(forKeyIfExists: "b", as: IntegerValue.self)?.value, 456)

    let ops2 = try await Interpreter.results(content: "<< /a 123 /b 456 >> begin /d where")
    expectEqual(ops2.count, 1)
    let bool2 = try requireValue(ops2[0].value as? BooleanValue, "Expected BooleanValue")
    expectEqual(bool2.value, false)

    let ops3 = try await Interpreter.results(content: "/c 789 def << /a 123 /b 456 >> begin /c where")
    expectEqual(ops3.count, 2)
    let bool3 = try requireValue(ops3[0].value as? BooleanValue, "Expected BooleanValue")
    expectEqual(bool3.value, true)
    let dict2 = try requireValue(ops3[1].value as? DictionaryValue, "Expected DictionaryValue")
    expectEqual(dict2.count, 1)
    expectEqual(try dict2.objectValue(forKeyIfExists: "c", as: IntegerValue.self)?.value, 789)
  }

  @Test
  func testCopy() async throws {
    let dict: DictionaryValue = try await Interpreter.result(content: "<< /a 123 /b 456 >> 10 dict copy")
    expectEqual(try dict.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 123)
    expectEqual(try dict.objectValue(forKeyIfExists: "b", as: IntegerValue.self)?.value, 456)
    expectEqual(try dict.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 123)
    expectEqual(try dict.objectValue(forKeyIfExists: "b", as: IntegerValue.self)?.value, 456)
  }

  @Test
  func testForAll() async throws {
    let ops = try await Interpreter.results(content: "<< /abc 123 /xyz (test) >> {} forall")
    guard ops.count == 4 else {
      return recordIssue("Expected 4 result operands")
    }
    let dict: [String?: Object?] = ops.chunks(ofCount: 2)
      .reduce([(String?, Object?)]()) { $0 + [(($1.last?.value as? NameValue)?.value, $1.first)] }
      .associated()
    expectEqual((dict["abc"]??.value as? IntegerValue)?.value, 123)
    expectEqual((dict["xyz"]??.value as? StringValue)?.string, "test")
  }

  @Test
  func testCurrentDict() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "/a 123 def currentdict")
    expectEqual(try dict1.objectValue(forKeyIfExists: "a", as: IntegerValue.self)?.value, 123)
  }

  @Test
  func testErrorDict() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "/a 123 def errordict")
    expectNil(try dict1.objectValue(forKeyIfExists: "a"))
  }

  @Test
  func testSystemDict() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "systemdict")
    expectEqual(try dict1.objectValue(forKeyIfExists: "begin", as: Operators.Begin.self), Operators.Begin.instance)
  }

  @Test
  func testUserDict() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "10 dict begin /a 123 def userdict")
    expectNil(try dict1.objectValue(forKeyIfExists: "a"))
  }

  @Test
  func testGlobalDict() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "/a 123 def globaldict")
    expectNil(try dict1.objectValue(forKeyIfExists: "a"))
  }

  @Test
  func testStatusDict() async throws {
    let dict1: DictionaryValue = try await Interpreter.result(content: "/a 123 def statusdict")
    expectNil(try dict1.objectValue(forKeyIfExists: "a"))
  }

  @Test
  func testCountDictStack() async throws {
    let int1: IntegerValue = try await Interpreter.result(content: "countdictstack")
    expectEqual(int1.value, 3)

    let int2: IntegerValue = try await Interpreter.result(content: "<< /a 123 /b 456 >> begin countdictstack")
    expectEqual(int2.value, 4)
  }

  @Test
  func testCopyDictStack() async throws {
    let array1: ArrayValue = try await Interpreter.result(content: "10 dict begin /abc 123 def 10 array dictstack")
    guard array1.count == 4 else {
      return recordIssue("Expected 4 elements")
    }
    let usrdict = try requireValue(array1.object(at: 0).value(as: DictionaryValue.self))
    expectEqual(try usrdict.objectValue(forKeyIfExists: "begin", as: Operators.Begin.self), Operators.Begin.instance)
    let sysdict = try requireValue(array1.object(at: 3).value(as: DictionaryValue.self))
    expectEqual(try sysdict.objectValue(forKeyIfExists: "abc", as: IntegerValue.self)?.value, 123)
  }

  @Test
  func testClearDictStack() async throws {
    let ctx1 = try await Interpreter.execute(content: "cleardictstack")
    let depth1 = await ctx1.dictionaryStackDepth
    expectEqual(depth1, 3)

    let ctx2 = try await Interpreter.execute(content: "10 dict dup begin begin countdictstack cleardictstack")
    let operand = try await ctx2.peekOperand()
    expectEqual((operand.value as? IntegerValue)?.value, 5)
    let depth2 = await ctx2.dictionaryStackDepth
    expectEqual(depth2, 3)
  }

}
