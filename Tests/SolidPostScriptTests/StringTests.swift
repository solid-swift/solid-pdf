//
//  StringTests.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct StringTests {

  @Test
  func testCreate() async throws {
    let str1: StringValue = try await Interpreter.result(content: "10 string")
    expectEqual(str1.count, 10)
    expectEqual(try str1.characters(in: str1.range), Data(repeating: 0, count: 10))
  }

  @Test
  func testLength() async throws {
    let len: IntegerValue = try await Interpreter.result(content: "10 string length")
    expectEqual(len.value, 10)
  }

  @Test
  func testGet() async throws {
    let char: IntegerValue = try await Interpreter.result(content: "(abcdef) 2 get")
    expectEqual(char.value, Character("c").asciiValue.map(Int.init))
  }

  @Test
  func testPut() async throws {
    let char: StringValue = try await Interpreter.result(content: "(abcdef) dup 2 32 put")
    expectEqual(char.string, "ab def")
  }

  @Test
  func testGetInterval() async throws {
    let char: StringValue = try await Interpreter.result(content: "(abcdef) 2 3 getinterval")
    expectEqual(char.string, "cde")
  }

  @Test
  func testPutInterval() async throws {
    let char: StringValue = try await Interpreter.result(content: "(abcdef) dup 3 (ghi) putinterval")
    expectEqual(char.string, "abcghi")
  }

  @Test
  func testCopy() async throws {
    let arr1: StringValue = try await Interpreter.result(content: "(abcdef) 7 string copy")
    expectEqual(arr1.string, "abcdef")
  }

  @Test
  func testForAll() async throws {
    let ints = try await Interpreter.result(content: "(abcdef) {} forall", count: 6, as: IntegerValue.self)
    expectEqual(ints[0].value, Character("f").asciiValue.map(Int.init))
    expectEqual(ints[1].value, Character("e").asciiValue.map(Int.init))
    expectEqual(ints[2].value, Character("d").asciiValue.map(Int.init))
    expectEqual(ints[3].value, Character("c").asciiValue.map(Int.init))
    expectEqual(ints[4].value, Character("b").asciiValue.map(Int.init))
    expectEqual(ints[5].value, Character("a").asciiValue.map(Int.init))
  }

  @Test
  func testAnchorSearch() async throws {
    typealias Result = (BooleanValue, StringValue, StringValue)
    let (result1, match, post) = try await Interpreter.result(content: "(abcdef) (ab) anchorsearch", as: Result.self)
    expectEqual(result1.value, true)
    expectEqual(match.string, "ab")
    expectEqual(post.string, "cdef")

    let (result2, string) =
      try await Interpreter.result(content: "(abcdef) (zx) anchorsearch", as: (BooleanValue, StringValue).self)
    expectEqual(result2.value, false)
    expectEqual(string.string, "abcdef")
  }

  @Test
  func testSearch() async throws {
    typealias Result = (BooleanValue, StringValue, StringValue, StringValue)
    let (result, pre, match, post) = try await Interpreter.result(content: "(abcdef) (cd) search", as: Result.self)
    expectEqual(result.value, true)
    expectEqual(pre.string, "ab")
    expectEqual(match.string, "cd")
    expectEqual(post.string, "ef")
  }

  @Test
  func testToken() async throws {
    typealias Result = (BooleanValue, NameValue, StringValue, NameValue)
    let ps = "(abc def ghi) token pop exch token"
    let (result, token2, post, token) = try await Interpreter.result(content: ps, as: Result.self)
    expectEqual(result.value, true)
    expectEqual(token2.value, "def")
    expectEqual(post.string, " ghi")
    expectEqual(token.value, "abc")
  }

  @Test
  func testExec() async throws {
    let ps = "(/abc /def /ghi) cvx exec"
    let names = try await Interpreter.result(content: ps, count: 3, as: NameValue.self)
    expectEqual(names.count, 3)
    expectEqual(names[0].value, "ghi")
    expectEqual(names[1].value, "def")
    expectEqual(names[2].value, "abc")
  }
}
