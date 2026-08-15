//
//  ComplexTests.swift
//
//
//  Created by Kevin Wooten on 7/1/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct ComplexTests {

  @Test
  func testConcatStrings() async throws {
    let ps =
      """
      /concatstrings % (a) (b) -> (ab)
      { exch dup length
       2 index length add string
       dup dup 4 2 roll copy length
       4 -1 roll putinterval
      } bind def
      (a) (b) concatstrings
      """

    let s = try await Interpreter.result(content: ps, as: StringValue.self)
    expectEqual(s.string, "ab")
  }

}
