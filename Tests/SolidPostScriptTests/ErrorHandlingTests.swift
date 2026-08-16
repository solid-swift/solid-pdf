//
//  ErrorHandlingTests.swift
//
import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct ErrorHandlingTests {

  @Test
  func `default handler records undefined and stopped catches it`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        {doesnotexist} stopped
        $error /command get
        $error /errorname get
        $error /newerror get
        """
    )

    expectEqual(results.count, 5)
    expectEqual(try results[0].value(as: BooleanValue.self).value, true)
    expectEqual(try results[1].value(as: NameValue.self).value, "undefined")
    expectEqual(try results[2].value(as: NameValue.self).value, "doesnotexist")
    expectEqual(try results[3].value(as: BooleanValue.self).value, true)
    expectEqual(try results[4].value(as: NameValue.self).value, "doesnotexist")
  }

  @Test
  func `error initiation restores operands and pushes the failing operator`() async throws {
    let results = try await Interpreter.results(content: "1 (bad) {add} stopped")

    expectEqual(results.count, 4)
    expectEqual(try results[0].value(as: BooleanValue.self).value, true)
    expectTrue(results[1].value is Operators.Add)
    expectEqual(try results[2].value(as: StringValue.self).string, "bad")
    expectEqual(try results[3].value(as: IntegerValue.self).value, 1)
  }

  @Test
  func `custom error handler can recover and resume execution`() async throws {
    let results = try await Interpreter.results(
      content: "errordict /undefined {pop 42} put doesnotexist 7"
    )

    expectEqual(results.count, 2)
    expectEqual(try results[0].value(as: IntegerValue.self).value, 7)
    expectEqual(try results[1].value(as: IntegerValue.self).value, 42)
  }

  @Test
  func `errors raised by a custom handler are dispatched normally`() async throws {
    let errorName: NameValue = try await Interpreter.result(
      content:
        """
        errordict /undefined {pop 1 (bad) add} put
        {doesnotexist} stopped clear
        $error /errorname get
        """
    )

    expectEqual(errorName.value, "typecheck")
  }

  @Test
  func `default handler records failure time stack snapshots`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        99 {doesnotexist} stopped clear
        $error /ostack get
        $error /estack get
        $error /dstack get
        """
    )

    let dictionaryStack = try results[0].value(as: ArrayValue.self)
    let executionStack = try results[1].value(as: ArrayValue.self)
    let operandStack = try results[2].value(as: ArrayValue.self)

    expectEqual(dictionaryStack.count, 3)
    expectEqual(executionStack.count, 2)
    expectEqual(operandStack.count, 1)
    expectEqual(try operandStack.object(at: 0).value(as: IntegerValue.self).value, 99)
  }

  @Test
  func `recordstacks false preserves existing snapshots`() async throws {
    let operandStack: ArrayValue = try await Interpreter.result(
      content:
        """
        $error /ostack [123] put
        $error /recordstacks false put
        {doesnotexist} stopped clear
        $error /ostack get
        """
    )

    expectEqual(operandStack.count, 1)
    expectEqual(try operandStack.object(at: 0).value(as: IntegerValue.self).value, 123)
  }

  @Test
  func `handleerror clears state without producing output`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        {doesnotexist} stopped clear
        errordict /handleerror get exec
        $error /newerror get
        $error /errorinfo get
        """
    )

    expectEqual(results.count, 2)
    expectTrue(results[0].value is NullValue)
    expectEqual(try results[1].value(as: BooleanValue.self).value, false)
  }

  @Test
  func `initial error dictionaries are complete writable and local`() async throws {
    let errorDictionary: DictionaryValue = try await Interpreter.result(content: "errordict")
    let expectedNames = [
      "configurationerror",
      "dictfull",
      "dictstackoverflow",
      "dictstackunderflow",
      "execstackoverflow",
      "interrupt",
      "invalidaccess",
      "invalidcontext",
      "invalidexit",
      "invalidfileaccess",
      "invalidfont",
      "invalidid",
      "invalidrestore",
      "ioerror",
      "limitcheck",
      "nocurrentpoint",
      "rangecheck",
      "stackoverflow",
      "stackunderflow",
      "syntaxerror",
      "timeout",
      "typecheck",
      "undefined",
      "undefinedfilename",
      "undefinedresource",
      "undefinedresult",
      "unmatchedmark",
      "unregistered",
      "VMerror",
      "handleerror",
    ]

    for name in expectedNames {
      expectTrue(try errorDictionary.object(forKeyIfExists: .literalName(name)) != nil, "Missing \(name)")
    }
    expectEqual(errorDictionary.access, .unlimited)
    expectEqual(errorDictionary.vm, .local)

    let checks: [BooleanValue] = try await Interpreter.result(content: "$error gcheck errordict gcheck", count: 2)
    expectEqual(checks[0].value, false)
    expectEqual(checks[1].value, false)
  }

  @Test
  func `restore reverts errordict changes`() async throws {
    let errorName: NameValue = try await Interpreter.result(
      content:
        """
        save
        errordict /undefined {pop 42} put
        restore
        {doesnotexist} stopped clear
        $error /errorname get
        """
    )

    expectEqual(errorName.value, "undefined")
  }

  @Test
  func `scanner errors record the executable source as command`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        <28> cvx stopped clear
        $error /errorname get
        $error /command get
        """
    )

    expectEqual(results.count, 2)
    expectEqual(try results[0].value(as: StringValue.self).string, "(")
    expectEqual(try results[1].value(as: NameValue.self).value, "syntaxerror")
  }

  @Test
  func `interrupt and timeout do not restore operands or push a command`() async throws {
    for error in [Error.interrupt, Error.timeout] {
      let results = try await execute(content: "1 {externalerror} stopped $error /command get", throwing: error)

      expectEqual(results.count, 2)
      expectTrue(results[0].value is NullValue)
      expectEqual(try results[1].value(as: BooleanValue.self).value, true)
    }
  }

  @Test
  func `uncaught errors preserve the Swift error contract`() async throws {
    do {
      _ = try await Interpreter.execute(content: "doesnotexist")
      recordIssue("Expected undefined error")
    } catch let error as Error {
      expectEqual(error, .undefined)
    }
  }

  @Test
  func `missing handler terminates with the newest language error`() async throws {
    do {
      _ = try await Interpreter.execute(content: "errordict /undefined undef doesnotexist")
      recordIssue("Expected undefined error")
    } catch let error as Error {
      expectEqual(error, .undefined)
    }
  }

  @Test
  func `unreadable errordict terminates without recursive dispatch`() async throws {
    do {
      _ = try await Interpreter.execute(content: "errordict noaccess pop doesnotexist")
      recordIssue("Expected invalidAccess error")
    } catch let error as Error {
      expectEqual(error, .invalidAccess)
    }
  }

  @Test
  func `explicit stop does not alter error state`() async throws {
    let results = try await Interpreter.results(
      content: "{stop} stopped $error /newerror get"
    )

    expectEqual(results.count, 2)
    expectEqual(try results[0].value(as: BooleanValue.self).value, false)
    expectEqual(try results[1].value(as: BooleanValue.self).value, true)
  }

  @Test
  func `default stop exits the innermost stopped context`() async throws {
    let results = try await Interpreter.results(content: "{{doesnotexist} stopped} stopped")

    expectEqual(results.count, 3)
    expectEqual(try results[0].value(as: BooleanValue.self).value, false)
    expectEqual(try results[1].value(as: BooleanValue.self).value, true)
    expectEqual(try results[2].value(as: NameValue.self).value, "doesnotexist")
  }

  @Test
  func `contexts isolate error handler changes`() async throws {
    async let customized = Interpreter.results(
      content: "errordict /undefined {pop 42} put doesnotexist"
    )
    async let standard: NameValue = Interpreter.result(
      content: "{doesnotexist} stopped clear $error /errorname get"
    )

    let (customizedResults, standardErrorName) = try await (customized, standard)
    expectEqual(try customizedResults[0].value(as: IntegerValue.self).value, 42)
    expectEqual(standardErrorName.value, "undefined")
  }

  private func execute(content: String, throwing error: Error) async throws -> [Object] {
    let context = Context()
    return try await context.executeForTesting(
      content: content,
      operatorValue: ExternalErrorOperator(error: error)
    )
  }
}

private struct ExternalErrorOperator: OperatorValue {
  static let systemDictionaryNames: [Object] = ["externalerror"]

  let error: Error

  func execute(context: isolated Context) async throws {
    _ = try context.operands.pop()
    throw error
  }

  func equals(_ other: any ObjectValue) -> Bool {
    other is Self
  }

  func hash(into hasher: inout Hasher) {
  }
}

extension Context {
  fileprivate func executeForTesting(content: String, operatorValue: any OperatorValue) async throws -> [Object] {
    try dictionaries.userDictionary().updateObject(.init(value: operatorValue), forKey: "externalerror")
    try await pushAndRun(
      source: .dataFile(
        content: Data(content.utf8),
        access: .readOnly,
        vm: .local,
        kind: .executable
      )
    )
    return try results()
  }
}
