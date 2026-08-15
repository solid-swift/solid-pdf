//
//  VMTests.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation
@testable import SolidPostScript
import Testing


@Suite
struct VMTests {

  @Test
  func testSaveRestoreObjects() async throws {
    let dict: DictionaryValue = try await Interpreter.result(
      content:
        """
        /a 10 def
        /b 20 def
        save
        dup /saved exch def
        /b 15 def
        /c 25 def
        restore
        userdict
        """
    )
    expectEqual(dict.count, 2)
    expectEqual(try dict.object(forKeyIfExists: "a")?.value(as: IntegerValue.self).value, 10)
    expectEqual(try dict.object(forKeyIfExists: "b")?.value(as: IntegerValue.self).value, 20)

    let dict2: DictionaryValue = try await Interpreter.result(
      content:
        """
        /a 10 def
        /b 20 def
        save
        /b 15 def
        /c 25 def
        save
        restore
        /d 30 def
        restore
        userdict
        """
    )
    expectEqual(dict2.count, 2)
    expectEqual(try dict2.object(forKeyIfExists: "a")?.value(as: IntegerValue.self).value, 10)
    expectEqual(try dict2.object(forKeyIfExists: "b")?.value(as: IntegerValue.self).value, 20)
  }

  @Test
  func testSaveRestoreIgnoreGlobals() async throws {
    let dict: DictionaryValue = try await Interpreter.result(
      content:
        """
        globaldict begin
        /a 10 def
        /b 20 def
        save
        /b 15 def
        /c 25 def
        restore
        currentdict
        """
    )
    expectEqual(dict.count, 3)
    expectEqual(try dict.object(forKeyIfExists: "a")?.value(as: IntegerValue.self).value, 10)
    expectEqual(try dict.object(forKeyIfExists: "b")?.value(as: IntegerValue.self).value, 15)
    expectEqual(try dict.object(forKeyIfExists: "c")?.value(as: IntegerValue.self).value, 25)
  }

  @Test
  func testInvalidRestore() async throws {
    do {
      _ = try await Interpreter.execute(
        content:
          """
          /a 10 def
          /b 20 def
          save
          /b 15 def
          /c 25 def
          save
          1 index
          restore
          """
      )
      recordIssue("Expected invalidRestore error")
    } catch let error as Error {
      expectTrue(error == Error.invalidRestore)
    }
    do {
      _ = try await Interpreter.execute(
        content:
          """
          /a 10 def
          /b 20 def
          save
          /b 15 def
          /c 25 def
          save
          /saved
          exch
          def
          restore
          """
      )
      recordIssue("Expected invalidRestore error")
    } catch let error as Error {
      expectTrue(error == Error.invalidRestore)
    }
  }

  @Test
  func testSetGlobal() async throws {
    let ctx = try await Interpreter.execute(content: "true setglobal")
    let mode = await ctx.allocationMode
    expectEqual(mode, .global)
  }

  @Test
  func testGetGlobal() async throws {
    let res1: BooleanValue = try await Interpreter.result(content: "currentglobal")
    expectEqual(res1.value, false)

    let res2: BooleanValue = try await Interpreter.result(content: "true setglobal currentglobal")
    expectEqual(res2.value, true)
  }

  @Test
  func testCheckGlobal() async throws {
    let res1: BooleanValue = try await Interpreter.result(content: "10 string gcheck")
    expectEqual(res1.value, false)

    let res2: BooleanValue = try await Interpreter.result(content: "true setglobal 10 string gcheck")
    expectEqual(res2.value, true)

    let res3: BooleanValue = try await Interpreter.result(content: "true gcheck")
    expectEqual(res3.value, true)
  }

  @Test
  func testStoreLocalInGlobalError() async throws {
    let ps = "true setglobal /a 10 dict false setglobal begin /a (abc) def"
    do {
      _ = try await Interpreter.execute(content: ps)
      recordIssue("Expected invalidAccess error")
    } catch let error as Error {
      expectEqual(error, Error.invalidAccess)
    }
  }

}
