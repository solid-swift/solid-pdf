//
//  ScannerTests.swift
//
//
//  Created by Kevin Wooten on 6/25/24.
//

import Foundation
import SolidCore
@testable import SolidPostScript
import Testing


@Suite
struct ScannerTests {

  func scan(_ content: String) throws -> [Token] {

    let scanner = try Scanner(content: content.data(using: .isoLatin1).neverNil())
    var tokens: [Token] = []

    while let token = try scanner.nextToken() {
      tokens.append(token)
    }

    return tokens
  }

  @Test
  func testLiteralStrings() async throws {

    expectEqual(
      try scan("(This is a string)"),
      [.string(Data("This is a string".utf8))]
    )

    expectEqual(
      try scan("(This is a string)(And another)"),
      [
        .string(Data("This is a string".utf8)),
        .string(Data("And another".utf8)),
      ]
    )

    expectEqual(
      try scan("(This is a string) (And another)"),
      [
        .string(Data("This is a string".utf8)),
        .string(Data("And another".utf8)),
      ]
    )

    expectEqual(
      try scan(
        """
        (This is a string) % literal strings are wrapped in parens
        (And another)
        """
      ),
      [
        .string(Data("This is a string".utf8)),
        .string(Data("And another".utf8)),
      ]
    )

    expectEqual(
      try scan("(Strings may contain special characters *-&}^% and balanced parentheses ( ) (and so on).)"),
      [.string(Data("Strings may contain special characters *-&}^% and balanced parentheses ( ) (and so on).".utf8))]
    )

    expectEqual(
      try scan(
        """
        (The following is an "empty" string.)
          ()
            (It has 0 (zero) length.)
        """
      ),
      [
        .string(Data(#"The following is an "empty" string."#.utf8)),
        .string(Data("".utf8)),
        .string(Data("It has 0 (zero) length.".utf8)),
      ]
    )

    expectEqual(
      try scan(
        """
        (Strings may contain newlines
        and such.)
        """
      ),
      [.string(Data("Strings may contain newlines\nand such.".utf8))]
    )

    expectEqual(
      try scan(
        """
        (These \\
        two strings \\
        are the same.)
        (These two strings are the same.)
        """
      ),
      [
        .string(Data("These two strings are the same.".utf8)),
        .string(Data("These two strings are the same.".utf8)),
      ]
    )

    expectEqual(
      try scan(
        """
        (This string has a newline at the end of it.
        )
        """ + "(So does this one.\n)"
      ),
      [
        .string(Data("This string has a newline at the end of it.\n".utf8)),
        .string(Data("So does this one.\n".utf8)),
      ]
    )

    expectEqual(
      try scan(
        """
        (  This string has a spaces at the beginning and end of it.
           )
        """
      ),
      [.string(Data("  This string has a spaces at the beginning and end of it.\n   ".utf8))]
    )

    expectEqual(
      try scan(#"(Escapes: \n \r \t \b \f \012 \x)"#),
      [.string(Data("Escapes: \n \r \t \u{08} \u{0C} \u{0A} x".utf8))]
    )

    expectEqual(
      try scan("(CRLF: 1\r\n2\\\r\n3)"),
      [.string(Data("CRLF: 1\n23".utf8))]
    )

    #expect(try scan("(a\\\nb)") == [.string(Data("ab".utf8))])
    #expect(try scan("(a\\\rb)") == [.string(Data("ab".utf8))])
    #expect(try scan("(a\\\r\nb)") == [.string(Data("ab".utf8))])
  }

  @Test
  func testHexEncodedStrings() async throws {

    #expect(try scan("<4142>") == [.string(Data("AB".utf8))])
    #expect(try scan("<A>") == [.string(Data([0xA0]))])

    expectEqual(
      try scan(
        """
        <2020204120737472696E672077697468202824255E262A5B5D3C3E292C0A2
        00A200A206E65776C696E65732C20616E642070616464696E672E2020>
        """
      ),
      [
        .string(
          Data(
            baseEncodedString:
              """
              2020204120737472696E672077697468202824255E262A5B5D3C3E292C0A2\
              00A200A206E65776C696E65732C20616E642070616464696E672E2020
              """,
            encoding: .base16
          )
          .neverNil()
        )
      ]
    )

    // Assuming zero for odd # of chars
    expectEqual(
      try scan(
        """
        <2020204120737472696E672077697468202824255E262A5B5D3C3E292C0A2
        00A200A206E65776C696E65732C20616E642070616464696E672E202>
        """
      ),
      [
        .string(
          Data(
            baseEncodedString:
              """
              2020204120737472696E672077697468202824255E262A5B5D3C3E292C0A2\
              00A200A206E65776C696E65732C20616E642070616464696E672E2020
              """,
            encoding: .base16
          )
          .neverNil()
        )
      ]
    )

    do {
      _ = try scan("<1020")
      recordIssue("Expected syntaxError")
    } catch {
      expectEqual(error as? Error, .syntaxError)
    }

    #expect(throws: Error.syntaxError) {
      try scan("<0G>")
    }
  }

  @Test
  func testAscii85EncodedStrings() async throws {
    expectEqual(
      try scan(
        """
        <~%h$*jn_Td@:pA-$l0[$kN#@:6~>
        """
      ),
      [.string(Data(base64Encoded: "Dwu+cPHenFxQsMuL6e3V8YwZhEA=").neverNil())]
    )

    #expect(try scan("<~~>") == [.string(Data())])
    #expect(try scan("<~!!~>") == [.string(Data([0]))])
    #expect(try scan("<~!!!~>") == [.string(Data([0, 0]))])
    #expect(try scan("<~!!!!~>") == [.string(Data([0, 0, 0]))])
    #expect(try scan("<~ z\t\r\n\u{0C}\u{0}~>") == [.string(Data(repeating: 0, count: 4))])
    #expect(try scan("<~>!!!!~>") == [.string(try Ascii85.decode(">!!!!"))])

    for malformed in ["<~!~>", "<~!z~>", "<~uuuuu~>", "<~!!>", "<~!!~x>", "<~!!"] {
      #expect(throws: Error.syntaxError) {
        try scan(malformed)
      }
    }
  }

  @Test
  func testMalformedAscii85UsesErrorDictionaryAndStopped() async throws {
    let results = try await Interpreter.results(
      content: "(<~!~>) cvx stopped $error /errorname get"
    )
    #expect(results.contains { ($0.value as? NameValue)?.value == "syntaxerror" })
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
  }

  @Test
  func testLiteralNames() async throws {

    expectEqual(
      try scan("/ThisIsALiteralName"),
      [.name("ThisIsALiteralName", kind: .literal)]
    )

    expectEqual(
      try scan("/LitName1/LitName2"),
      [
        .name("LitName1", kind: .literal),
        .name("LitName2", kind: .literal),
      ]
    )

    expectEqual(
      try scan("/LitName1 /LitName2"),
      [
        .name("LitName1", kind: .literal),
        .name("LitName2", kind: .literal),
      ]
    )

    expectEqual(
      try scan(
        """
        /LitName1 % a comment
        /LitName2
        """
      ),
      [
        .name("LitName1", kind: .literal),
        .name("LitName2", kind: .literal),
      ]
    )
  }

  @Test
  func testImmediateBoundNames() async throws {

    expectEqual(
      try scan("//ThisIsALiteralName"),
      [.name("/ThisIsALiteralName", kind: .literal)]
    )

    expectEqual(
      try scan("//LitName1//LitName2"),
      [
        .name("/LitName1", kind: .literal),
        .name("/LitName2", kind: .literal),
      ]
    )

    expectEqual(
      try scan("//LitName1 //LitName2"),
      [
        .name("/LitName1", kind: .literal),
        .name("/LitName2", kind: .literal),
      ]
    )

    expectEqual(
      try scan(
        """
        //LitName1 % a comment
        //LitName2
        """
      ),
      [
        .name("/LitName1", kind: .literal),
        .name("/LitName2", kind: .literal),
      ]
    )

    expectEqual(try scan("//"), [.name("/", kind: .literal)])
  }

  @Test
  func testExecutableNames() async throws {

    expectEqual(
      try scan(
        """
        abc Offset $$ 23A           % examples from the
        13-456 a.b $MyDict @pattern % PostScript Reference
        """
      ),
      [
        .name("abc", kind: .executable),
        .name("Offset", kind: .executable),
        .name("$$", kind: .executable),
        .name("23A", kind: .executable),
        .name("13-456", kind: .executable),
        .name("a.b", kind: .executable),
        .name("$MyDict", kind: .executable),
        .name("@pattern", kind: .executable),
      ]
    )
  }

  @Test
  func testOperatorNames() async throws {

    expectEqual(
      try scan(
        """
        mark [ << { ] >> }
        """
      ),
      [
        .name("mark", kind: .executable),
        .name("[", kind: .executable),
        .name("<<", kind: .executable),
        .name("{", kind: .executable),
        .name("]", kind: .executable),
        .name(">>", kind: .executable),
        .name("}", kind: .executable),
      ]
    )

    // Ensure < & << are distinctly recognized
    expectEqual(
      try scan(
        """
        <q <$ <\\ <%
        q> $> \\> >%
        <
        <<
        >>
        < < > >
        """
      ),
      [
        .name("<", kind: .executable),
        .name("q", kind: .executable),
        .name("<", kind: .executable),
        .name("$", kind: .executable),
        .name("<", kind: .executable),
        .name("\\", kind: .executable),
        .name("<", kind: .executable),
        .name("q", kind: .executable),
        .name(">", kind: .executable),
        .name("$", kind: .executable),
        .name(">", kind: .executable),
        .name("\\", kind: .executable),
        .name(">", kind: .executable),
        .name(">", kind: .executable),
        .name("<", kind: .executable),
        .name("<<", kind: .executable),
        .name(">>", kind: .executable),
        .name("<", kind: .executable),
        .name("<", kind: .executable),
        .name(">", kind: .executable),
        .name(">", kind: .executable),
      ]
    )

    // Ensure < & << are distinctly recognized
    expectEqual(
      try scan(
        """
        <
        """
      ),
      [
        .name("<", kind: .executable)
      ]
    )

  }

  @Test
  func testDictionaryLiteralDemlims() {
    expectEqual(
      try scan(
        """
        <<q>>
        << q>>
        <<q >>
        """
      ),
      [
        .name("<<", kind: .executable),
        .name("q", kind: .executable),
        .name(">>", kind: .executable),
        .name("<<", kind: .executable),
        .name("q", kind: .executable),
        .name(">>", kind: .executable),
        .name("<<", kind: .executable),
        .name("q", kind: .executable),
        .name(">>", kind: .executable),
      ]
    )
    expectEqual(
      try scan(
        """
        <<1>>
        <<1 >>
        << 1>>
        """
      ),
      [
        .name("<<", kind: .executable),
        .integer(1),
        .name(">>", kind: .executable),
        .name("<<", kind: .executable),
        .integer(1),
        .name(">>", kind: .executable),
        .name("<<", kind: .executable),
        .integer(1),
        .name(">>", kind: .executable),
      ]
    )
    expectEqual(
      try scan(
        """
        <<[1]>>
        <<[1 ] >>
        << [ 1]>>
        """
      ),
      [
        .name("<<", kind: .executable),
        .name("[", kind: .executable),
        .integer(1),
        .name("]", kind: .executable),
        .name(">>", kind: .executable),
        .name("<<", kind: .executable),
        .name("[", kind: .executable),
        .integer(1),
        .name("]", kind: .executable),
        .name(">>", kind: .executable),
        .name("<<", kind: .executable),
        .name("[", kind: .executable),
        .integer(1),
        .name("]", kind: .executable),
        .name(">>", kind: .executable),
      ]
    )
    expectEqual(
      try scan(
        """
        <<<<q>>>>
        <<<<1>>>>
        """
      ),
      [
        .name("<<", kind: .executable),
        .name("<<", kind: .executable),
        .name("q", kind: .executable),
        .name(">>", kind: .executable),
        .name(">>", kind: .executable),
        .name("<<", kind: .executable),
        .name("<<", kind: .executable),
        .integer(1),
        .name(">>", kind: .executable),
        .name(">>", kind: .executable),
      ]
    )
  }

  @Test
  func testCommentSpecial() {
    expectEqual(try scan("abc%"), [.name("abc", kind: .executable)])
    expectEqual(try scan("abc%\r"), [.name("abc", kind: .executable)])
    expectEqual(try scan("abc%\n"), [.name("abc", kind: .executable)])
    expectEqual(try scan("abc%\r\n"), [.name("abc", kind: .executable)])
  }

  @Test
  func testWhitespaceSpecial() {
    expectEqual(try scan("abc   "), [.name("abc", kind: .executable)])
    expectEqual(try scan(" "), [])
  }

  @Test
  func testEmpty() {
    expectEqual(try scan(""), [])
  }

  @Test
  func testIntegers() {
    expectEqual(try scan("123"), [.integer(123)])
    expectEqual(try scan("-98"), [.integer(-98)])
    expectEqual(try scan("43445"), [.integer(43445)])
    expectEqual(try scan("0"), [.integer(0)])
    expectEqual(try scan("+17"), [.integer(+17)])
  }

  @Test
  func testRadixIntegers() {
    expectEqual(try scan("8#1777"), [.integer(0o1777)])
    expectEqual(try scan("16#FFFE"), [.integer(0xfffe)])
    expectEqual(try scan("2#1000"), [.integer(0b1000)])
  }

  @Test
  func testReals() {
    expectEqual(try scan("123.456"), [.real(123.456)])
    expectEqual(try scan("-.002"), [.real(-0.002)])
    expectEqual(try scan("34.5"), [.real(34.5)])
    expectEqual(try scan("-3.62"), [.real(-3.62)])
    expectEqual(try scan("123.6e10"), [.real(123.6e10)])
    expectEqual(try scan("1.0E-5"), [.real(1.0E-5)])
    expectEqual(try scan("1E6"), [.real(1E6)])
    expectEqual(try scan("-1."), [.real(-1.0)])
    expectEqual(try scan("0.0"), [.real(0.0)])
  }

  @Test
  func testAvailable() async throws {
    let scanner = try Scanner(content: "123 456".data(using: .isoLatin1).neverNil())
    guard try scanner.nextToken() != nil else {
      return recordIssue("Token expected")
    }
    expectEqual(try scanner.available, 4)
  }

}
