//
//  ConversionTests.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct ConversionTests {

  @Test
  func testConvertToInteger() async throws {
    let res1 = try await Interpreter.results(content: "123.456 cvi")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .integer)
    expectEqual((res1[0].value as? IntegerValue)?.value, 123)

    let res2 = try await Interpreter.results(content: "(123) cvi")
    expectEqual(res2.count, 1)
    expectEqual(res2[0].type, .integer)
    expectEqual((res2[0].value as? IntegerValue)?.value, 123)

    let res3 = try await Interpreter.results(content: "(123.456) cvi")
    expectEqual(res3.count, 1)
    expectEqual(res3[0].type, .integer)
    expectEqual((res3[0].value as? IntegerValue)?.value, 123)

    let res4 = try await Interpreter.results(content: "123 cvi")
    expectEqual(res4.count, 1)
    expectEqual(res4[0].type, .integer)
    expectEqual((res4[0].value as? IntegerValue)?.value, 123)

    do {
      _ = try await Interpreter.results(content: "/a cvi")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.typeCheck)
    }
  }

  @Test
  func testConvertToReal() async throws {
    let res1 = try await Interpreter.results(content: "123 cvr")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .real)
    expectEqual((res1[0].value as? RealValue)?.value, 123.0)

    let res2 = try await Interpreter.results(content: "(123.456) cvr")
    expectEqual(res2.count, 1)
    expectEqual(res2[0].type, .real)
    expectEqual((res2[0].value as? RealValue)?.value, 123.456)

    let res3 = try await Interpreter.results(content: "(123) cvr")
    expectEqual(res3.count, 1)
    expectEqual(res3[0].type, .real)
    expectEqual((res3[0].value as? RealValue)?.value, 123.0)

    let res4 = try await Interpreter.results(content: "123.456 cvr")
    expectEqual(res4.count, 1)
    expectEqual(res4[0].type, .real)
    expectEqual((res4[0].value as? RealValue)?.value, 123.456)

    do {
      _ = try await Interpreter.results(content: "/a cvr")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.typeCheck)
    }
  }

  @Test
  func testConvertToString() async throws {
    let res1 = try await Interpreter.results(content: "123.456 100 string cvs")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .string)
    expectEqual((res1[0].value as? StringValue)?.string, "123.456")

    let res2 = try await Interpreter.results(content: "123 100 string cvs")
    expectEqual(res2.count, 1)
    expectEqual(res2[0].type, .string)
    expectEqual((res2[0].value as? StringValue)?.string, "123")

    let res3 = try await Interpreter.results(content: "true 100 string cvs")
    expectEqual(res3.count, 1)
    expectEqual(res3[0].type, .string)
    expectEqual((res3[0].value as? StringValue)?.string, "true")

    let res4 = try await Interpreter.results(content: "(abcde) 100 string cvs")
    expectEqual(res4.count, 1)
    expectEqual(res4[0].type, .string)
    expectEqual((res4[0].value as? StringValue)?.string, "abcde")

    let res5 = try await Interpreter.results(content: "/abcde 100 string cvs")
    expectEqual(res5.count, 1)
    expectEqual(res5[0].type, .string)
    expectEqual((res5[0].value as? StringValue)?.string, "abcde")

    let res6 = try await Interpreter.results(content: "/token load 100 string cvs")
    expectEqual(res6.count, 1)
    expectEqual(res6[0].type, .string)
    expectEqual((res6[0].value as? StringValue)?.string, "token")

    do {
      _ = try await Interpreter.results(content: "123 1 string cvs")
      recordIssue("Expected rangeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.rangeCheck)
    }
  }

  @Test
  func testConvertToStringWithRadix() async throws {
    let res1 = try await Interpreter.results(content: "123 10 100 string cvrs")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .string)
    expectEqual((res1[0].value as? StringValue)?.string, "123")

    let res2 = try await Interpreter.results(content: "-123 10 100 string cvrs")
    expectEqual(res2.count, 1)
    expectEqual(res2[0].type, .string)
    expectEqual((res2[0].value as? StringValue)?.string, "-123")

    let res3 = try await Interpreter.results(content: "123.4 10 100 string cvrs")
    expectEqual(res3.count, 1)
    expectEqual(res3[0].type, .string)
    expectEqual((res3[0].value as? StringValue)?.string, "123.4")

    let res4 = try await Interpreter.results(content: "123 16 100 string cvrs")
    expectEqual(res4.count, 1)
    expectEqual(res4[0].type, .string)
    expectEqual((res4[0].value as? StringValue)?.string, "7B")

    let res5 = try await Interpreter.results(content: "-123 16 100 string cvrs")
    expectEqual(res5.count, 1)
    expectEqual(res5[0].type, .string)
    expectEqual((res5[0].value as? StringValue)?.string, "-7B")

    let res6 = try await Interpreter.results(content: "123.4 16 100 string cvrs")
    expectEqual(res6.count, 1)
    expectEqual(res6[0].type, .string)
    expectEqual((res6[0].value as? StringValue)?.string, "7B")
  }

  @Test
  func testConvertToName() async throws {
    let res1 = try await Interpreter.results(content: "(aa) cvn")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .name)
    expectEqual(res1[0].valueString, "aa")

    do {
      _ = try await Interpreter.results(content: "3 cvn")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.typeCheck)
    }
  }

}
