//
//  AccessRestrictionTests.swift
//

import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct AccessRestrictionTests {

  @Test
  func `string equality uses only the selected intervals`() async throws {
    let equal: BooleanValue = try await Interpreter.result(
      content: "(xabcx) 1 3 getinterval (yabcy) 1 3 getinterval eq"
    )

    #expect(equal.value)
  }

  @Test
  func `string ordering uses only the selected intervals`() async throws {
    let ordered: BooleanValue = try await Interpreter.result(
      content: "(zab) 1 2 getinterval (aac) 1 2 getinterval lt"
    )

    #expect(ordered.value)
  }

  @Test
  func `host string comparison uses only the selected intervals`() throws {
    let first = try StringValue(
      sharing: StringValue(string: "zab", access: .unlimited, vm: .local),
      subRange: 1..<3
    )
    let second = try StringValue(
      sharing: StringValue(string: "aac", access: .unlimited, vm: .local),
      subRange: 1..<3
    )
    #expect(first.compare(second) == .orderedAscending)
  }

  @Test
  func `search uses the selected receiver and needle intervals`() async throws {
    typealias Result = (BooleanValue, StringValue, StringValue, StringValue)
    let (found, prefix, match, suffix) = try await Interpreter.result(
      content: "(XabcY) 1 3 getinterval (ZbcQ) 1 2 getinterval search",
      as: Result.self
    )

    #expect(found.value)
    #expect(prefix.string == "a")
    #expect(match.string == "bc")
    #expect(suffix.string.isEmpty)
  }

  @Test
  func `anchorsearch uses the selected receiver and needle intervals`() async throws {
    typealias Result = (StringValue, StringValue, StringValue, StringValue)
    let (suffix, match, needle, source) = try await Interpreter.result(
      content:
        """
        /source (XabcY) def
        /searched source 1 3 getinterval def
        /needleBacking (ZabQ) def
        /needle needleBacking 1 2 getinterval def
        searched needle anchorsearch
        pop /match exch def /suffix exch def
        match 0 81 put
        source needle match suffix
        """,
      as: Result.self
    )

    #expect(source.string == "XQbcY")
    #expect(needle.string == "ab")
    #expect(match.string == "Qb")
    #expect(suffix.string == "c")
    #expect(match.allocation === source.allocation)
    #expect(match.allocation !== needle.allocation)
  }

  @Test
  func `numeric conversions read only the selected string interval`() async throws {
    let integer: IntegerValue = try await Interpreter.result(content: "(x123y) 1 3 getinterval cvi")
    let real: RealValue = try await Interpreter.result(content: "(x12.5y) 1 4 getinterval cvr")

    #expect(integer.value == 123)
    #expect(real.value == 12.5)
  }

  @Test
  func `cvn preserves the string execution kind`() async throws {
    let literal: BooleanValue = try await Interpreter.result(content: "(abc) cvn xcheck")
    let executable: BooleanValue = try await Interpreter.result(content: "(abc) cvx cvn xcheck")

    #expect(!literal.value)
    #expect(executable.value)
  }

  @Test(
    arguments: [
      "(a) noaccess (a) eq",
      "(a) (a) executeonly ne",
      "/a (a) noaccess eq",
      "(a) executeonly /a eq",
      "(a) noaccess (b) lt",
      "(a) (b) executeonly ge",
      "(a) noaccess (longer) anchorsearch",
      "(abc) (b) noaccess search",
      "(1) noaccess cvi",
      "(1.5) executeonly cvr",
      "(name) noaccess cvn",
      "(value) noaccess 16 string cvs",
      "() noaccess token",
      "() noaccess print",
    ]
  )
  func `string content operators reject unreadable operands`(_ operation: String) async throws {
    let errorName: NameValue = try await Interpreter.result(
      content: "{ \(operation) } stopped clear $error /errorname get"
    )

    #expect(errorName.value == "invalidaccess")
  }

  @Test(
    arguments: [
      "[] noaccess length",
      "true setpacking {} noaccess length",
      "() noaccess length",
      "0 dict noaccess maxlength",
      "[] noaccess 0 0 getinterval",
      "true setpacking {} noaccess 0 0 getinterval",
      "() executeonly 0 0 getinterval",
      "[] noaccess {} forall",
      "true setpacking {} noaccess {} forall",
      "() noaccess {} forall",
    ]
  )
  func `structural reads reject inaccessible composites even when empty`(_ operation: String) async throws {
    let errorName: NameValue = try await Interpreter.result(
      content: "{ \(operation) } stopped clear $error /errorname get"
    )

    #expect(errorName.value == "invalidaccess")
  }

  @Test
  func `access failures retain operator attribution and operand rollback`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        42 { (a) noaccess (a) eq } stopped
        $error /command get /eq load eq
        $error /errorname get
        """
    )

    #expect(try results[0].value(as: NameValue.self).value == "invalidaccess")
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: BooleanValue.self).value)
    #expect(results[3].value is Operators.Equal)
    #expect(try results[4].value(as: StringValue.self).string == "a")
    #expect(try results[5].value(as: StringValue.self).string == "a")
    #expect(try results[6].value(as: IntegerValue.self).value == 42)
  }
}
