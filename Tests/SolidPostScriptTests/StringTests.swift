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
    expectEqual(char.value, Character("c").asciiValue.map(Int32.init))
  }

  @Test
  func testPut() async throws {
    let char: StringValue = try await Interpreter.result(content: "(abcdef) dup 2 32 put")
    expectEqual(char.string, "ab def")
  }

  @Test
  func testGetInterval() async throws {
    let results = try await Interpreter.results(content: "(abcdef) 2 3 getinterval")
    #expect(results.count == 1)
    let string = try #require(results.first?.value as? StringValue)
    expectEqual(string.string, "cde")
  }

  @Test
  func testGetIntervalSharesCharacters() async throws {
    let (interval, string) = try await Interpreter.result(
      content: "/s (abcdef) def /i s 2 3 getinterval def i 0 88 put s i",
      as: (StringValue, StringValue).self
    )
    expectEqual(interval.string, "Xde")
    expectEqual(string.string, "abXdef")
  }

  @Test
  func testPutInterval() async throws {
    let char: StringValue = try await Interpreter.result(content: "(abcdef) dup 3 (ghi) putinterval")
    expectEqual(char.string, "abcghi")
  }

  @Test
  func testOverlappingPutInterval() async throws {
    let string: StringValue = try await Interpreter.result(
      content: "/s (abcde) def s 1 s 0 4 getinterval putinterval s"
    )
    expectEqual(string.string, "aabcd")
  }

  @Test
  func testCopy() async throws {
    let arr1: StringValue = try await Interpreter.result(content: "(abcdef) 7 string copy")
    expectEqual(arr1.string, "abcdef")
  }

  @Test
  func testForAll() async throws {
    let ints = try await Interpreter.result(content: "(abcdef) {} forall", count: 6, as: IntegerValue.self)
    expectEqual(ints[0].value, Character("f").asciiValue.map(Int32.init))
    expectEqual(ints[1].value, Character("e").asciiValue.map(Int32.init))
    expectEqual(ints[2].value, Character("d").asciiValue.map(Int32.init))
    expectEqual(ints[3].value, Character("c").asciiValue.map(Int32.init))
    expectEqual(ints[4].value, Character("b").asciiValue.map(Int32.init))
    expectEqual(ints[5].value, Character("a").asciiValue.map(Int32.init))
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
  func anchorSearchReturnsViewsOfTheSearchedString() async throws {
    typealias Result = (StringValue, StringValue, StringValue, StringValue)
    let (post, match, needle, source) = try await Interpreter.result(
      content:
        """
        /source (abcdef) def
        /needle (ab) def
        source needle anchorsearch
        pop /match exch def /post exch def
        match 0 88 put
        post 0 89 put
        source needle match post
        """,
      as: Result.self
    )

    #expect(source.string == "XbYdef")
    #expect(needle.string == "ab")
    #expect(match.string == "Xb")
    #expect(post.string == "Ydef")
    #expect(match.allocation === source.allocation)
    #expect(post.allocation === source.allocation)
    #expect(match.allocation !== needle.allocation)
  }

  @Test
  func anchorSearchResultsInheritTheSearchedStringAttributes() async throws {
    let results = try await Interpreter.results(
      content:
        """
        true setglobal
        /source (abcdef) cvx readonly def
        false setglobal
        /needle (ab) def
        /source load needle anchorsearch
        """
    )

    #expect(results.count == 3)
    #expect(try results[0].value(as: BooleanValue.self).value)
    let match = try results[1].value(as: StringValue.self)
    let post = try results[2].value(as: StringValue.self)
    #expect(match.vm == .global)
    #expect(post.vm == .global)
    #expect(match.access == .readOnly)
    #expect(post.access == .readOnly)
    #expect(results[1].kind == .executable)
    #expect(results[2].kind == .executable)
  }

  @Test
  func anchorSearchPreservesSearchedViewIdentityForEmptyAndMissingNeedles() async throws {
    let matchedResults = try await Interpreter.results(
      content: "/source (XabcY) 1 3 getinterval def source source () anchorsearch"
    )
    let matched = try matchedResults[1].value(as: StringValue.self)
    let matchedPost = try matchedResults[2].value(as: StringValue.self)
    let matchedOriginal = try matchedResults[3].value(as: StringValue.self)
    #expect(matched.count == 0)
    #expect(matched.allocation === matchedOriginal.allocation)
    #expect(matchedPost.allocation === matchedOriginal.allocation)
    #expect(matched.refRange.lowerBound == matchedPost.refRange.lowerBound)

    let missingResults = try await Interpreter.results(
      content: "/source (XabcY) 1 3 getinterval def source source (z) anchorsearch"
    )
    let returned = try missingResults[1].value(as: StringValue.self)
    let retained = try missingResults[2].value(as: StringValue.self)
    #expect(returned.string == "abc")
    #expect(returned.allocation === retained.allocation)
    #expect(returned.refRange == retained.refRange)
    #expect(returned.access == retained.access)
  }

  @Test
  func anchorSearchAccessErrorsUseTheLanguageErrorLifecycle() async throws {
    let results = try await Interpreter.results(
      content:
        """
        42 { (abc) (a) noaccess anchorsearch } stopped
        $error /command get /anchorsearch load eq
        $error /errorname get
        """
    )

    #expect(try results[0].value(as: NameValue.self).value == "invalidaccess")
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: BooleanValue.self).value)
    #expect(results[3].value is Operators.AnchorSearch)
    #expect(try results[4].value(as: StringValue.self).string == "a")
    #expect(try results[5].value(as: StringValue.self).string == "abc")
    #expect(try results[6].value(as: IntegerValue.self).value == 42)
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
    expectEqual(post.string, "ghi")
    expectEqual(token.value, "abc")
  }

  @Test
  func stringTokenConsumesOneCompleteWhitespaceSeparator() async throws {
    let space: StringValue = try await Interpreter.result(content: "(abc def) token pop pop")
    let carriageReturn: StringValue = try await Interpreter.result(content: "(abc\\rdef) token pop pop")
    let lineFeed: StringValue = try await Interpreter.result(content: "(abc\\ndef) token pop pop")
    let carriageReturnLineFeed: StringValue = try await Interpreter.result(
      content: "(abc\\r\\ndef) token pop pop"
    )
    let delimiter: StringValue = try await Interpreter.result(content: "(abc/def) token pop pop")

    #expect(space.string == "def")
    #expect(carriageReturn.string == "def")
    #expect(lineFeed.string == "def")
    #expect(carriageReturnLineFeed.string == "def")
    #expect(delimiter.string == "/def")
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
