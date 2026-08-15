//
//  AttributeTests.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct AttributeTests {

  @Test
  func testType() async throws {
    let res1: StringValue = try await Interpreter.result(content: "true type")
    expectEqual(res1.string, "booleantype")

    let res2: StringValue = try await Interpreter.result(content: "10 type")
    expectEqual(res2.string, "integertype")

    let res3: StringValue = try await Interpreter.result(content: "10.1 type")
    expectEqual(res3.string, "realtype")

    let res4: StringValue = try await Interpreter.result(content: "/a type")
    expectEqual(res4.string, "nametype")

    let res5: StringValue = try await Interpreter.result(content: "/add load type")
    expectEqual(res5.string, "operatortype")

    let res6: StringValue = try await Interpreter.result(content: "mark type")
    expectEqual(res6.string, "marktype")

    let res7: StringValue = try await Interpreter.result(content: "() type")
    expectEqual(res7.string, "stringtype")

    let res8: StringValue = try await Interpreter.result(content: "[] type")
    expectEqual(res8.string, "arraytype")

    let res9: StringValue = try await Interpreter.result(content: "<< >> type")
    expectEqual(res9.string, "dicttype")

    let res10: StringValue = try await Interpreter.result(content: "{} type")
    expectEqual(res10.string, "arraytype")

    let res11: StringValue = try await Interpreter.result(content: "1 1 packedarray type")
    expectEqual(res11.string, "packedarraytype")

    let res12: StringValue = try await Interpreter.result(content: "null type")
    expectEqual(res12.string, "nulltype")
  }

  @Test
  func testChangeToLiteral() async throws {
    let res1 = try await Interpreter.results(content: "{} cvlit")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .literal)
  }

  @Test
  func testChangeToExecutable() async throws {
    let res1 = try await Interpreter.results(content: "(a) cvx")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .string)
    expectEqual(res1[0].kind, .executable)
  }

  @Test
  func testReduceToExecuteOnly() async throws {
    let res1 = try await Interpreter.results(content: "{} executeonly")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .executable)
    expectEqual((res1[0].value as? ArrayValue)?.access, .executeOnly)

    do {
      _ = try await Interpreter.results(content: "[] noaccess executeonly")
      recordIssue("Expected invalidAccess error")
    } catch let error as Error {
      expectTrue(error == Error.invalidAccess)
    }
  }

  @Test
  func testReduceToReadOnly() async throws {
    let res1 = try await Interpreter.results(content: "{} readonly")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .executable)
    expectEqual((res1[0].value as? ArrayValue)?.access, .readOnly)

    do {
      _ = try await Interpreter.results(content: "[] executeonly readonly")
      recordIssue("Expected invalidAccess error")
    } catch let error as Error {
      expectTrue(error == Error.invalidAccess)
    }
  }

  @Test
  func testReduceToNoAccess() async throws {
    let res1 = try await Interpreter.results(content: "{} noaccess")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .array)
    expectEqual(res1[0].kind, .executable)
    expectEqual((res1[0].value as? ArrayValue)?.access, .noAccess)
  }

  @Test
  func testTestExecutableAttribute() async throws {
    let res1 = try await Interpreter.results(content: "(a) xcheck")
    expectEqual(res1.count, 1)
    expectEqual(try res1[0].value(as: BooleanValue.self).value, false)

    let res2 = try await Interpreter.results(content: "{} xcheck")
    expectEqual(res2.count, 1)
    expectEqual(try res2[0].value(as: BooleanValue.self).value, true)
  }

  @Test
  func testTestReadableAttribute() async throws {
    let res1 = try await Interpreter.results(content: "(a) rcheck")
    expectEqual(res1.count, 1)
    expectEqual(try res1[0].value(as: BooleanValue.self).value, true)

    let res2 = try await Interpreter.results(content: "{} rcheck")
    expectEqual(res2.count, 1)
    expectEqual(try res2[0].value(as: BooleanValue.self).value, true)

    let res3 = try await Interpreter.results(content: "{} noaccess rcheck")
    expectEqual(res3.count, 1)
    expectEqual(try res3[0].value(as: BooleanValue.self).value, false)

    do {
      _ = try await Interpreter.results(content: "false rcheck")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.typeCheck)
    }
  }

  @Test
  func testTestWritableAttribute() async throws {
    let res1 = try await Interpreter.results(content: "(a) wcheck")
    expectEqual(res1.count, 1)
    expectEqual(try res1[0].value(as: BooleanValue.self).value, true)

    let res2 = try await Interpreter.results(content: "{} wcheck")
    expectEqual(res2.count, 1)
    expectEqual(try res2[0].value(as: BooleanValue.self).value, true)

    do {
      _ = try await Interpreter.results(content: "false wcheck")
      recordIssue("Expected typeCheck error")
    } catch let error as Error {
      expectTrue(error == Error.typeCheck)
    }
  }

}
