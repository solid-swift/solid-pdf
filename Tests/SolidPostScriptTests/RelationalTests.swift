//
//  RelationalTests.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
import SolidPostScript
import Testing


@Suite
struct RelationalTests {

  // MARK: Equlas (eq)

  @Test
  func testEqualRealInt() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.0 4 eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 3 eq")
    expectEqual(bool2.value, false)

  }

  @Test
  func testEqualIntReal() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 4.0 eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "3 4.0 eq")
    expectEqual(bool2.value, false)

  }

  @Test
  func testEqualInts() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 4 eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 3 eq")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "4 /a eq")
    expectEqual(bool3.value, false)

  }

  @Test
  func testEqualReals() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.0 4.0 eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 3.0 eq")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "4.0 /a eq")
    expectEqual(bool3.value, false)
  }

  @Test
  func testEqualStrings() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "(abc) (abc) eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "(abc) (def) eq")
    expectEqual(bool2.value, false)
  }

  @Test
  func testEqualNames() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "/a /a eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "/a /b eq")
    expectEqual(bool2.value, false)
  }

  @Test
  func testEqualNamesStrings() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "/a (a) eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "/a (b) eq")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "(a) /a eq")
    expectEqual(bool3.value, true)

    let bool4: BooleanValue = try await Interpreter.result(content: "(a) /b eq")
    expectEqual(bool4.value, false)
  }

  @Test
  func testEqualBools() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "true true eq")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "true false eq")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "true /a eq")
    expectEqual(bool3.value, false)
  }

  // MARK: Not Equals (ne)

  @Test
  func testNotEqualRealInt() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.0 4 ne")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 3 ne")
    expectEqual(bool2.value, true)

  }

  @Test
  func testNotEqualIntReal() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 4.0 ne")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "3 4.0 ne")
    expectEqual(bool2.value, true)

  }

  @Test
  func testNotEqualInts() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 4 ne")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 3 ne")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "4 /a ne")
    expectEqual(bool3.value, true)

  }

  @Test
  func testNotEqualReals() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.0 4.0 ne")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 3.0 ne")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "4.0 /a ne")
    expectEqual(bool3.value, true)
  }

  @Test
  func testNotEqualStrings() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "(abc) (abc) ne")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "(abc) (def) ne")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "(abc) /a ne")
    expectEqual(bool3.value, true)
  }

  @Test
  func testNotEqualNames() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "/a /a ne")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "/a /b ne")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "/a (b) ne")
    expectEqual(bool3.value, true)
  }

  @Test
  func testNotEqualBools() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "true true ne")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "true false ne")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "true /a ne")
    expectEqual(bool3.value, true)
  }

  // MARK: Great Than Or Equal To (ge)

  @Test
  func testGreaterThanOrEqualRealInt() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4 ge")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4 ge")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4 ge")
    expectEqual(bool3.value, false)

  }

  @Test
  func testGreaterThanOrEqualIntReal() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3.0 ge")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4.0 ge")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4.0 ge")
    expectEqual(bool3.value, false)
  }

  @Test
  func testGreaterThanOrEqualInts() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3 ge")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4 ge")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4 ge")
    expectEqual(bool3.value, false)
  }

  @Test
  func testGreaterThanOrEqualReals() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4.0 ge")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4.0 ge")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4.0 ge")
    expectEqual(bool3.value, false)
  }

  @Test
  func testGreaterThanOrEqualStrings() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "(ac) (ab) ge")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "(ab) (ab) ge")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "(ab) (ac) ge")
    expectEqual(bool3.value, false)
  }

  // MARK: Great Than (gt)

  @Test
  func testGreaterThanRealInt() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4 gt")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4 gt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4 gt")
    expectEqual(bool3.value, false)

  }

  @Test
  func testGreaterThanIntReal() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3.0 gt")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4.0 gt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4.0 gt")
    expectEqual(bool3.value, false)
  }

  @Test
  func testGreaterThanInts() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3 gt")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4 gt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4 gt")
    expectEqual(bool3.value, false)
  }

  @Test
  func testGreaterThanReals() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4.0 gt")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4.0 gt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4.0 gt")
    expectEqual(bool3.value, false)
  }

  @Test
  func testGreaterThanStrings() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "(ac) (ab) gt")
    expectEqual(bool1.value, true)

    let bool2: BooleanValue = try await Interpreter.result(content: "(ab) (ab) gt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "(ab) (ac) gt")
    expectEqual(bool3.value, false)
  }

  // MARK: Less Than Or Equal To (le)

  @Test
  func testLessThanOrEqualRealInt() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4 le")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4 le")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4 le")
    expectEqual(bool3.value, true)

  }

  @Test
  func testLessThanOrEqualIntReal() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3.0 le")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4.0 le")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4.0 le")
    expectEqual(bool3.value, true)
  }

  @Test
  func testLessThanOrEqualInts() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3 le")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4 le")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4 le")
    expectEqual(bool3.value, true)
  }

  @Test
  func testLessThanOrEqualReals() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4.0 le")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4.0 le")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4.0 le")
    expectEqual(bool3.value, true)
  }

  @Test
  func testLessThanOrEqualStrings() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "(ac) (ab) le")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "(ab) (ab) le")
    expectEqual(bool2.value, true)

    let bool3: BooleanValue = try await Interpreter.result(content: "(ab) (ac) le")
    expectEqual(bool3.value, true)
  }

  // MARK: Less Than (gt)

  @Test
  func testLessThanRealInt() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4 lt")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4 lt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4 lt")
    expectEqual(bool3.value, true)

  }

  @Test
  func testLessThanIntReal() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3.0 lt")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4.0 lt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4.0 lt")
    expectEqual(bool3.value, true)
  }

  @Test
  func testLessThanInts() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4 3 lt")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4 4 lt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3 4 lt")
    expectEqual(bool3.value, true)
  }

  @Test
  func testLessThanReals() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "4.2 4.0 lt")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "4.0 4.0 lt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "3.0 4.0 lt")
    expectEqual(bool3.value, true)
  }

  @Test
  func testLessThanStrings() async throws {

    let bool1: BooleanValue = try await Interpreter.result(content: "(ac) (ab) lt")
    expectEqual(bool1.value, false)

    let bool2: BooleanValue = try await Interpreter.result(content: "(ab) (ab) lt")
    expectEqual(bool2.value, false)

    let bool3: BooleanValue = try await Interpreter.result(content: "(ab) (ac) lt")
    expectEqual(bool3.value, true)
  }

}
