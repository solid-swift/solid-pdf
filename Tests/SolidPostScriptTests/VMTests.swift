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
    #expect(try systemDictionary.object(forKey: "shareddict") == dictionaries[1])

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
    expectEqual(dict.count, 3)
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
    expectEqual(dict2.count, 3)
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
    _ = try await Interpreter.execute(
      content:
        """
        /a 10 def
        /b 20 def
        save
        /b 15 def
        /c 25 def
        save
        /saved exch def
        restore
        """
    )
  }

  @Test(arguments: [
    "save /s exch def 0 array s restore",
    "save /s exch def 0 string s restore",
    "save /s exch def 0 dict s restore",
    "save /s exch def 0 packedarray s restore",
    "save /s exch def (%stdout) (w) file /ASCIIHexEncode filter s restore",
    "save /s exch def 0 dict begin s restore",
    "save /s exch def { s restore 0 } exec",
  ])
  func restoreRejectsPostSaveLocalCompositesOnInterpreterStacks(_ content: String) async {
    await #expect(throws: Error.invalidRestore) {
      try await Interpreter.execute(content: content)
    }
  }

  @Test
  func tailPositionRestoreDoesNotRetainItsProcedureOnTheExecutionStack() async throws {
    _ = try await Interpreter.execute(content: "save /s exch def {s restore} exec")
  }

  @Test
  func standardFilesPredateSaveAndPreserveTheirAllocationIdentity() async throws {
    let results = try await Interpreter.results(
      content:
        """
        save /s exch def
        true setglobal
        (%stdin) (r) file
        (%stdout) (w) file
        (%stderr) (w) file
        s restore
        (%stdin) (r) file
        (%stdout) (w) file
        (%stderr) (w) file
        """
    )

    #expect(results.count == 6)
    for index in 0..<3 {
      let afterRestore = try results[index].value(as: FileValue.self)
      let beforeRestore = try results[index + 3].value(as: FileValue.self)
      #expect(afterRestore.vm == .local)
      #expect(beforeRestore.vm == .local)
      #expect(afterRestore.allocation === beforeRestore.allocation)
      #expect(afterRestore.file === beforeRestore.file)
    }
  }

  @Test
  func restoreDoesNotReopenAClosedStandardFile() async throws {
    let results = try await Interpreter.results(
      content:
        """
        (%stdout) (w) file /standard exch def
        save /s exch def
        standard closefile
        s restore
        { (%stdout) (w) file (unreachable) writestring } stopped
        /didStop exch def
        clear
        didStop standard
        """
    )

    #expect(try results[0].value(as: FileValue.self).file.isClosed)
    #expect(try results[1].value(as: BooleanValue.self).value)
  }

  @Test
  func invalidRestoreUsesErrorLifecycleWithoutDiscardingOperands() async throws {
    let results = try await Interpreter.results(
      content:
        """
        save /s exch def
        0 array
        { s restore } stopped
        $error /errorname get /invalidrestore eq
        $error /command get /restore load eq
        """
    )

    let checks = results.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(checks == [true, true, true])
    #expect(results.contains { $0.value is ArrayValue })
  }

  @Test
  func restoreAllowsGlobalAndPreSaveIntervalObjects() async throws {
    let global: BooleanValue = try await Interpreter.result(
      content: "save /s exch def true setglobal 0 array false setglobal s restore gcheck"
    )
    #expect(global.value)

    for content in [
      "/value [1 2] def value 0 1 getinterval",
      "/value (ab) def value 0 1 getinterval",
      "/value 3 4 2 packedarray def value 0 1 getinterval",
    ] {
      let restored: BooleanValue = try await Interpreter.result(
        content: "\(content) save /s exch def s restore pop true"
      )
      #expect(restored.value)
    }
  }

  @Test
  func restoreChecksOnlyDirectStackObjects() async throws {
    let restored: BooleanValue = try await Interpreter.result(
      content:
        """
        /outer 1 array def
        save /s exch def
        outer 0 1 array put
        outer s restore
        outer 0 get null eq
        """
    )

    #expect(restored.value)
  }

  @Test
  func saveObjectsAreLocalCompositeValuesWithIdentity() async throws {
    let checks: [BooleanValue] = try await Interpreter.result(
      content: "save dup gcheck exch dup eq",
      count: 2
    )

    #expect(checks.map(\.value) == [true, false])
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
  func sharedVMCompatibilityAliasesTrackGlobalVM() async throws {
    let checks: [BooleanValue] = try await Interpreter.result(
      content:
        """
        currentshared
        false setshared 1 string scheck
        true setshared 1 string scheck
        true scheck
        save false setshared restore currentshared
        """,
      count: 5
    )

    #expect(checks.map(\.value) == [true, true, true, false, false])
  }

  @Test
  func sharedDictionaryIsGlobalWritableAndUnaffectedByRestore() async throws {
    let checks: [BooleanValue] = try await Interpreter.result(
      content:
        """
        shareddict globaldict eq
        shareddict gcheck
        shareddict wcheck
        shareddict /probe 1 put
        save shareddict /probe 2 put restore
        shareddict /probe get 2 eq
        """,
      count: 4
    )

    #expect(checks.allSatisfy { $0.value })
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
  func restorePreservesLocalStringContentsAndAliases() async throws {
    let (interval, string) = try await Interpreter.result(
      content:
        """
        /s (abcdef) def
        /i s 2 3 getinterval def
        save i 0 88 put restore
        s i
        """,
      as: (StringValue, StringValue).self
    )

    #expect(string.string == "abXdef")
    #expect(interval.string == "Xde")
  }

  @Test
  func restorePreservesDistinctEqualStringMutations() async throws {
    let (second, first) = try await Interpreter.result(
      content:
        """
        /a (same) def
        /b (same) def
        save a 0 65 put b 0 66 put restore
        a b
        """,
      as: (StringValue, StringValue).self
    )

    #expect(first.string == "Aame")
    #expect(second.string == "Bame")
  }

  @Test
  func restoreDoesNotRevertGlobalStringContents() async throws {
    let string: StringValue = try await Interpreter.result(
      content: "true setglobal /s (abc) def false setglobal save s 0 120 put restore s"
    )
    #expect(string.string == "xbc")
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
