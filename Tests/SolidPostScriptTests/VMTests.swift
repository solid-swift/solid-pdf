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
  func standardDictionariesUseExpectedDomainsAccessAndIdentity() throws {
    let dictionaries = Context.defaultDictionaries()
    let userDictionary = try dictionaries[0].value(as: DictionaryValue.self)
    let globalDictionary = try dictionaries[1].value(as: DictionaryValue.self)
    let systemDictionary = try dictionaries[2].value(as: DictionaryValue.self)

    #expect(userDictionary.vm == .local)
    #expect(userDictionary.access == .unlimited)
    #expect(globalDictionary.vm == .global)
    #expect(globalDictionary.access == .unlimited)
    #expect(systemDictionary.vm == .global)
    #expect(systemDictionary.access == .readOnly)

    let errorState = try systemDictionary.objectValue(forKey: "$error", as: DictionaryValue.self)
    let errorDictionary = try systemDictionary.objectValue(forKey: "errordict", as: DictionaryValue.self)
    let statusDictionary = try systemDictionary.objectValue(forKey: "statusdict", as: DictionaryValue.self)

    #expect(errorState.vm == .local)
    #expect(errorState.access == .unlimited)
    #expect(errorDictionary.vm == .local)
    #expect(errorDictionary.access == .unlimited)
    #expect(statusDictionary.vm == .local)
    #expect(statusDictionary.access == .unlimited)
    #expect(try systemDictionary.object(forKey: "systemdict") == dictionaries[2])

    let otherDictionaries = Context.defaultDictionaries()
    #expect(dictionaries[0] != otherDictionaries[0])
    #expect(dictionaries[1] != otherDictionaries[1])
    #expect(dictionaries[2] != otherDictionaries[2])
  }

  @Test
  func dictionaryStackKeepsStandardOrdering() async throws {
    let stack: ArrayValue = try await Interpreter.result(content: "3 array dictstack")
    let systemDictionary = try stack.object(at: 0).value(as: DictionaryValue.self)
    let globalDictionary = try stack.object(at: 1).value(as: DictionaryValue.self)
    let userDictionary = try stack.object(at: 2).value(as: DictionaryValue.self)

    #expect(systemDictionary.vm == .global)
    #expect(globalDictionary.vm == .global)
    #expect(userDictionary.vm == .local)
  }

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
  func scannerStringsUseCurrentAllocationMode() async throws {
    let checks: [BooleanValue] = try await Interpreter.result(
      content:
        """
        true setglobal
        (abc) gcheck
        <6162> gcheck
        <~%h$*jn_Td@:pA-$l0[$kN#@:6~> gcheck
        """,
      count: 3
    )

    #expect(checks.map { $0.value } == [true, true, true])
  }

  @Test
  func restoreRevertsAllocationPackingAndLocalStandardDictionaries() async throws {
    let checks: [BooleanValue] = try await Interpreter.result(
      content:
        """
        save
        true setglobal
        true setpacking
        $error /recordstacks false put
        statusdict /probe true put
        restore
        currentglobal
        currentpacking
        $error /recordstacks get
        statusdict /probe known
        """,
      count: 4
    )

    #expect(checks.map(\.value) == [false, true, false, false])
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

  @Test
  func publicDictionaryMutationRejectsLocalCompositeInGlobalVM() throws {
    let dictionary = try DictionaryValue(value: [:], access: .unlimited, vm: .global)
    let localString = Object.string("local", access: .unlimited, vm: .local, kind: .literal)

    #expect(throws: Error.invalidAccess) {
      try dictionary.setObject(localString, forKey: "value")
    }
  }

}
