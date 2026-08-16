//
//  DictionaryVMAccountingTests.swift
//

@testable import SolidPostScript
import Testing

@Suite
struct DictionaryVMAccountingTests {

  @Test
  func `dictionary copy fails atomically when local VM is exhausted`() async throws {
    typealias Result = (NameValue, BooleanValue, IntegerValue, BooleanValue, IntegerValue)
    let (errorName, commandMatches, count, copiedKeyKnown, sentinel) = try await Interpreter.result(
      content:
        """
        /source << /a 1 /b 2 >> def
        /destination << /sentinel 42 >> def
        /operation { source destination copy } def
        << /MaxLocalVM 1 >> setuserparams
        /operation load stopped clear
        destination /sentinel get
        destination /a known
        destination length
        $error /command get /copy load eq
        $error /errorname get
        """,
      as: Result.self
    )

    #expect(errorName.value == "VMerror")
    #expect(commandMatches.value)
    #expect(count.value == 1)
    #expect(!copiedKeyKnown.value)
    #expect(sentinel.value == 42)
  }

  @Test
  func `dictionary copy restores operands after VMerror`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /source << /a 1 >> def
        /destination 0 dict def
        /operation { source destination copy } def
        << /MaxLocalVM 1 >> setuserparams
        17 /operation load stopped
        """
    )

    #expect(results.count == 5)
    #expect(try results[0].value(as: BooleanValue.self).value)
    #expect(results[1].value is Operators.Copy)
    #expect(try results[2].value(as: DictionaryValue.self).count == 0)
    #expect(try results[3].value(as: DictionaryValue.self).count == 1)
    #expect(try results[4].value(as: IntegerValue.self).value == 17)
  }

  @Test
  func `dictionary copy does not charge replacements`() async throws {
    let values: [IntegerValue] = try await Interpreter.result(
      content:
        """
        /source << /a 1 /b 2 >> def
        /destination << /a 9 /b 8 >> def
        << /MaxLocalVM 1 >> setuserparams
        source destination copy
        dup /a get exch /b get
        """,
      count: 2
    )

    #expect(values.map(\.value) == [2, 1])
  }

  @Test
  func `dictionary copy charges only new normalized keys`() async throws {
    typealias Result = (NameValue, BooleanValue, IntegerValue, BooleanValue)
    let (errorName, copiedKeyKnown, original, aliasKnown) = try await Interpreter.result(
      content:
        """
        /source << (a) 1 /b 2 >> def
        /destination << /a 9 >> def
        /operation { source destination copy } def
        << /MaxLocalVM 1 >> setuserparams
        /operation load stopped clear
        destination /a known
        destination /a get
        destination /b known
        $error /errorname get
        """,
      as: Result.self
    )

    #expect(errorName.value == "VMerror")
    #expect(!copiedKeyKnown.value)
    #expect(original.value == 9)
    #expect(aliasKnown.value)
  }

  @Test
  func `self copy succeeds without local VM capacity`() async throws {
    let value: IntegerValue = try await Interpreter.result(
      content:
        """
        /dictionary << /a 1 >> def
        << /MaxLocalVM 1 >> setuserparams
        dictionary dictionary copy /a get
        """
    )

    #expect(value.value == 1)
  }

  @Test
  func `global dictionary growth ignores MaxLocalVM`() async throws {
    let value: IntegerValue = try await Interpreter.result(
      content:
        """
        /source << /a 1 >> def
        true setglobal /destination 1 dict def false setglobal
        << /MaxLocalVM 1 >> setuserparams
        source destination copy /a get
        """
    )

    #expect(value.value == 1)
  }

  @Test
  func `storage errors precede local VM accounting`() async throws {
    typealias Result = (NameValue, BooleanValue)
    let (errorName, keyKnown) = try await Interpreter.result(
      content:
        """
        /source << /a (local) >> def
        true setglobal /destination 1 dict def false setglobal
        /operation { source destination copy } def
        << /MaxLocalVM 1 >> setuserparams
        /operation load stopped clear
        destination /a known
        $error /errorname get
        """,
      as: Result.self
    )

    #expect(errorName.value == "invalidaccess")
    #expect(!keyKnown.value)
  }

  @Test(
    arguments: [
      "dictionary /new 1 put",
      "dictionary begin /new 1 def end",
      "dictionary begin /new 1 store end",
    ]
  )
  func `single entry operators share local VM enforcement`(_ operation: String) async throws {
    let results = try await Interpreter.results(
      content:
        """
        /dictionary 0 dict def
        /operation { \(operation) } def
        << /MaxLocalVM 1 >> setuserparams
        /operation load stopped clear
        dictionary /new known
        $error /errorname get
        """
    )

    #expect(results.count == 2)
    #expect(try results[0].value(as: NameValue.self).value == "VMerror")
    #expect(try !results[1].value(as: BooleanValue.self).value)
  }

  @Test
  func `failed user object expansion preserves the existing table`() async throws {
    typealias Result = (NameValue, IntegerValue, StringValue)
    let (errorName, length, original) = try await Interpreter.result(
      content:
        """
        0 (old) defineuserobject
        /operation { 50 2 defineuserobject } def
        << /MaxLocalVM 1 >> setuserparams
        /operation load stopped clear
        UserObjects 0 get
        UserObjects length
        $error /errorname get
        """,
      as: Result.self
    )

    #expect(errorName.value == "VMerror")
    #expect(length.value == 50)
    #expect(original.string == "old")
  }

  @Test
  func `stale prepared mutations do not overwrite newer dictionary state`() throws {
    let source = try DictionaryValue(value: ["source": 1], access: .unlimited, vm: .local)
    let destination = try DictionaryValue(value: [:], access: .unlimited, vm: .local)
    let mutation = try destination.prepareUpdateObjects(forKeysIn: source)

    try destination.updateObject(2, forKey: "newer")

    #expect(try !destination.commit(mutation))
    #expect(try destination.object(forKeyIfExists: "source") == nil)
    #expect(try destination.objectValue(forKey: "newer", as: IntegerValue.self).value == 2)
  }
}
