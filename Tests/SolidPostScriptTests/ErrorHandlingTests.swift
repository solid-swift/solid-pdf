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
  func `compatibility alias errors retain operand rollback and command identity`() async throws {
    let commandMatches: BooleanValue = try await Interpreter.result(
      content: "{1 setshared} stopped clear $error /command get /setshared load eq"
    )

    #expect(commandMatches.value)
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
    expectEqual(try executionStack.object(at: 1), .executableName("stopped"))
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
  func `parameter errors record the offending key and value`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        $error /recordstacks false put
        { << /MaxOpStack (bad) >> setuserparams } stopped clear
        $error /errorinfo get
        $error /command get /setuserparams load eq
        $error /errorname get
        """
    )

    expectEqual(try results[0].value(as: NameValue.self).value, "typecheck")
    expectEqual(try results[1].value(as: BooleanValue.self).value, true)
    let errorInfo = try results[2].value(as: ArrayValue.self)
    expectEqual(errorInfo.count, 2)
    expectEqual(try errorInfo.object(at: 0).value(as: NameValue.self).value, "MaxOpStack")
    expectEqual(try errorInfo.object(at: 1).value(as: StringValue.self).string, "bad")
  }

  @Test
  func `missing password records the expected key with null`() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (secret) >> setsystemparams",
      environment: environment
    )

    let results = try await Interpreter.results(
      content:
        """
        { << /PrinterName (Denied) >> setsystemparams } stopped clear
        $error /errorinfo get
        $error /errorname get
        """,
      environment: environment
    )

    expectEqual(try results[0].value(as: NameValue.self).value, "invalidaccess")
    let errorInfo = try results[1].value(as: ArrayValue.self)
    expectEqual(try errorInfo.object(at: 0).value(as: NameValue.self).value, "Password")
    expectTrue(try errorInfo.object(at: 1).value is NullValue)
  }

  @Test
  func `nonparameter failures clear prior error information`() async throws {
    let result: NullValue = try await Interpreter.result(
      content:
        """
        { << /MaxOpStack (bad) >> setuserparams } stopped clear
        {doesnotexist} stopped clear
        $error /errorinfo get
        """
    )

    expectTrue(result == .instance)
  }

  @Test
  func `device providers can report structured parameter failures`() async throws {
    let environment = InterpreterEnvironment(
      fileDevices: FileDevices(devices: [RejectingParameterizedDevice()])
    )
    let errorInfo: ArrayValue = try await Interpreter.result(
      content:
        """
        { (%reject%) << /BufferSize -1 >> setdevparams } stopped clear
        $error /errorinfo get
        """,
      environment: environment
    )

    expectEqual(try errorInfo.object(at: 0).value(as: NameValue.self).value, "BufferSize")
    expectEqual(try errorInfo.object(at: 1).value(as: IntegerValue.self).value, -1)
  }

  @Test
  func `parameter keys are validated but dictionary access errors have no entry metadata`() async throws {
    let invalidKeyInfo: ArrayValue = try await Interpreter.result(
      content:
        """
        { << 1 2 >> setuserparams } stopped clear
        $error /errorinfo get
        """
    )
    expectEqual(try invalidKeyInfo.object(at: 0).value(as: IntegerValue.self).value, 1)
    expectEqual(try invalidKeyInfo.object(at: 1).value(as: IntegerValue.self).value, 2)

    let inaccessible: NullValue = try await Interpreter.result(
      content:
        """
        /parameters << /MaxOpStack (bad) >> noaccess def
        { parameters setuserparams } stopped clear
        $error /errorinfo get
        """
    )
    expectTrue(inaccessible == .instance)
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

  @Test
  func `stackoverflow handler receives the operand stack as one array`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /handlerDepth null def
        /recovery null def
        errordict /stackoverflow {
          count /handlerDepth exch store
          /recovery exch store
        } put
        /overflow { 1 2 3 4 5 } def
        << /MaxOpStack 4 >> setuserparams
        overflow
        handlerDepth recovery
        """
    )

    let recovery = try results[0].value(as: ArrayValue.self)
    expectEqual(try recoveryIntegers(recovery), [1, 2, 3, 4])
    expectEqual(try results[1].value(as: IntegerValue.self).value, 1)
  }

  @Test
  func `default stackoverflow recovery preserves command and stack metadata`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /defaultStackOverflow errordict /stackoverflow get def
        errordict /stackoverflow {
          << /MaxOpStack 100 >> setuserparams
          defaultStackOverflow exec
        } put
        /overflow { 1 2 3 4 5 } def
        << /MaxOpStack 4 >> setuserparams
        /overflow load stopped
        $error /command get
        $error /ostack get
        """
    )

    let recorded = try results[0].value(as: ArrayValue.self)
    expectEqual(try recoveryIntegers(recorded), [1, 2, 3, 4])
    expectEqual(try results[1].value(as: IntegerValue.self).value, 5)
    expectEqual(try results[2].value(as: BooleanValue.self).value, true)
    let recovery = try results[3].value(as: ArrayValue.self)
    expectEqual(try recoveryIntegers(recovery), [1, 2, 3, 4])
  }

  @Test
  func `stackoverflow recovery bypasses tiny stack and local VM limits`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        $error /recordstacks false put
        /overflow { 1 2 } def
        << /MaxLocalVM 0 /MaxOpStack 1 >> setuserparams
        /overflow load stopped
        """
    )

    expectEqual(try results[0].value(as: BooleanValue.self).value, true)
    let recovery = try results[1].value(as: ArrayValue.self)
    expectEqual(try recoveryIntegers(recovery), [1])
  }

  @Test
  func `dictstackoverflow handler receives dictstack and permanent recovery state`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /recovery null def
        /handlerDepth null def
        /overflowing << /marker 1 >> def
        errordict /dictstackoverflow {
          /recovery exch store
          /handlerDepth countdictstack store
        } put
        << /MaxDictStack 4 >> setuserparams
        overflowing begin
        1 dict begin
        handlerDepth recovery
        """
    )

    let recovery = try results[0].value(as: ArrayValue.self)
    expectEqual(recovery.count, 4)
    expectEqual(try results[1].value(as: IntegerValue.self).value, 3)
    expectTrue(results[2].value is Operators.Begin)
    expectTrue(results[3].value is DictionaryValue)

    let recoveredTop = try recovery.object(at: 3).value(as: DictionaryValue.self)
    expectEqual(try recoveredTop.objectValue(forKey: "marker", as: IntegerValue.self).value, 1)
  }

  @Test
  func `default dictstackoverflow handler preserves failure time dictionary metadata`() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /defaultDictStackOverflow errordict /dictstackoverflow get def
        errordict /dictstackoverflow {
          << /MaxDictStack 100 >> setuserparams
          defaultDictStackOverflow exec
        } put
        << /MaxDictStack 4 >> setuserparams
        1 dict begin
        { 1 dict begin } stopped
        $error /dstack get
        $error /command get /begin load eq
        """
    )

    expectEqual(try results[0].value(as: BooleanValue.self).value, true)
    let dictionaryStack = try results[1].value(as: ArrayValue.self)
    expectEqual(dictionaryStack.count, 4)
    expectEqual(try results[2].value(as: BooleanValue.self).value, true)
    let recovery = try results[3].value(as: ArrayValue.self)
    expectEqual(recovery.count, 4)
  }

  @Test
  func `bulk push stackoverflow recovery remains atomic`() async throws {
    let recovery: ArrayValue = try await Interpreter.result(
      content:
        """
        /recovery null def
        errordict /stackoverflow { /recovery exch store } put
        << /MaxOpStack 3 >> setuserparams
        1 2 2 copy
        recovery
        """
    )

    expectEqual(try recoveryIntegers(recovery), [1, 2])
  }

  @Test
  func `nested stackoverflow handlers receive fresh recovery arrays`() async throws {
    let recovery: ArrayValue = try await Interpreter.result(
      content:
        """
        /handling false def
        /recovery null def
        errordict /stackoverflow {
          handling
            { /recovery exch store }
            {
              /handling true store
              pop
              1 2 3 4 5
            }
          ifelse
        } put
        << /MaxOpStack 4 >> setuserparams
        1 2 3 4 5
        recovery
        """
    )

    expectEqual(try recoveryIntegers(recovery), [1, 2, 3, 4])
  }

  @Test
  func `uncaught stackoverflow preserves the Swift error contract`() async {
    await #expect(throws: Error.stackOverflow) {
      try await Interpreter.execute(
        content:
          """
          /overflow { 1 2 } def
          << /MaxOpStack 1 >> setuserparams
          overflow
          """
      )
    }
  }

  private func recoveryIntegers(_ array: ArrayValue) throws -> [Int32] {
    try (0..<array.count).map {
      try array.object(at: $0).value(as: IntegerValue.self).value
    }
  }

  private func execute(content: String, throwing error: Error) async throws -> [Object] {
    let context = Context()
    return try await context.executeForTesting(
      content: content,
      operatorValue: ExternalErrorOperator(error: error)
    )
  }
}

private struct RejectingParameterizedDevice: ParameterizedFileDevice {
  let name = "reject"
  let searched = false

  func open(name: String, mode: File.Mode, openMethod: OpenMethod) throws -> File {
    throw Error.undefinedFilename
  }

  func currentParameters() throws -> [Object: Object] { [:] }

  func setParameters(_ parameters: [Object: Object]) throws {
    let key = Object.literalName("BufferSize")
    throw PostScriptParameterFailure(error: .rangeCheck, key: key, value: parameters[key])
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
