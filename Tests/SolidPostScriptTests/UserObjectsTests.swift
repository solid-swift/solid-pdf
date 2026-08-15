//
//  UserObjectsTests.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct UserObjectsTests {

  @Test
  func testDefine() async throws {
    let res1: ArrayValue? = try? await Interpreter.result(content: "17 (abc) defineuserobject UserObjects")
    expectEqual(res1?.count, 50)
    expectEqual(try res1?.object(at: 17).value(as: StringValue.self).string, "abc")

    let res2: ArrayValue? = try? await Interpreter.result(content: "27 (abc) defineuserobject UserObjects")
    expectEqual(res2?.count, 54)
    expectEqual(try res2?.object(at: 27).value(as: StringValue.self).string, "abc")
  }

  @Test
  func testExec() async throws {
    let res1: StringValue? = try? await Interpreter.result(content: "17 (abc) defineuserobject 17 execuserobject")
    expectEqual(res1?.string, "abc")

    do {
      _ = try await Interpreter.results(content: "17 execuserobject")
      recordIssue("Expected undefined error")
    } catch let error as Error {
      expectEqual(error, Error.undefined)
    }

    do {
      _ = try await Interpreter.results(content: "17 (abc) defineuserobject 100 execuserobject")
      recordIssue("Expected rangeCheck error")
    } catch let error as Error {
      expectEqual(error, Error.rangeCheck)
    }
  }

  @Test
  func testUndefine() async throws {
    let res1: ArrayValue? = try? await Interpreter.result(
      content: "1 1 defineuserobject 1 undefineuserobject UserObjects"
    )
    expectEqual(res1?.count, 50)
    expectEqual(try res1?.object(at: 1), .null)

    _ = try await Interpreter.results(content: "17 undefineuserobject")

    do {
      _ = try await Interpreter.results(content: "17 (abc) defineuserobject 100 execuserobject")
      recordIssue("Expected rangeCheck error")
    } catch let error as Error {
      expectEqual(error, Error.rangeCheck)
    }
  }

}
