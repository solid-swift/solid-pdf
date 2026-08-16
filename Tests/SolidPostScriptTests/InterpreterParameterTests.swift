//
//  InterpreterParameterTests.swift
//  SolidPostScriptTests
//

import Foundation
@testable import SolidPostScript
import Synchronization
import Testing

@Suite
struct InterpreterParameterTests {

  @Test
  func publishesCompleteParameterCatalogsAndFreshDictionaries() async throws {
    let user: DictionaryValue = try await Interpreter.result(content: "currentuserparams")
    let system: DictionaryValue = try await Interpreter.result(content: "currentsystemparams")

    let userKeys = Set(try user.keys.map { try $0.value(as: NameValue.self).value })
    let systemKeys = Set(try system.keys.map { try $0.value(as: NameValue.self).value })
    let readableSystemKeys = Set(SystemParameterState.definitions.keys)
      .subtracting(["SystemParamsPassword", "StartJobPassword"])
      .union(UserParameterState.definitions.keys)
    #expect(userKeys == Set(UserParameterState.definitions.keys))
    #expect(systemKeys == readableSystemKeys)
    #expect(try user.objectValue(forKey: "IdiomRecognition", as: BooleanValue.self).value)
    #expect(try user.objectValue(forKey: "JobName", as: StringValue.self).count == 0)
    #expect(try system.objectValue(forKey: "RealFormat", as: StringValue.self).nameString == "IEEE")

    let distinct: BooleanValue = try await Interpreter.result(
      content: "currentuserparams currentuserparams ne"
    )
    #expect(distinct.value)
  }

  @Test
  func userUpdatesNormalizeCopyAndCommitTransactionally() async throws {
    let values = try await Interpreter.results(
      content:
        """
        << /HalftoneMode 99 /VMReclaim -99 /JobName (abc\000ignored) /Unknown 1 >> setuserparams
        currentuserparams /HalftoneMode get
        currentuserparams /VMReclaim get
        currentuserparams /JobName get
        """
    )
    #expect(try values[0].value(as: StringValue.self).nameString == "abc")
    #expect(try values[1].value(as: IntegerValue.self).value == -2)
    #expect(try values[2].value(as: IntegerValue.self).value == 2)

    let retained: StringValue = try await Interpreter.result(
      content:
        """
        << /JobName (abc) >> setuserparams
        { << /JobName (changed) /MaxOpStack (bad) >> setuserparams } stopped clear
        currentuserparams /JobName get
        """
    )
    #expect(retained.nameString == "abc")

    let truncated: IntegerValue = try await Interpreter.result(
      content:
        "<< /JobName (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa) >> setuserparams currentuserparams /JobName get length"
    )
    #expect(truncated.value == 100)
  }

  @Test
  func userParametersRestoreAndRemainContextLocal() async throws {
    let restored: StringValue = try await Interpreter.result(
      content:
        """
        save
        << /JobName (temporary) >> setuserparams
        restore
        currentuserparams /JobName get
        """
    )
    #expect(restored.count == 0)

    let environment = InterpreterEnvironment()
    async let first: StringValue = Interpreter.result(
      content: "<< /JobName (first) >> setuserparams currentuserparams /JobName get",
      environment: environment
    )
    async let second: StringValue = Interpreter.result(
      content: "currentuserparams /JobName get",
      environment: environment
    )
    #expect(try await first.nameString == "first")
    #expect(try await second.nameString == "")
  }

  @Test
  func systemUpdatesAreSharedWithFutureContextsAndPasswordProtected() async throws {
    let environment = InterpreterEnvironment()
    let existingDefault: IntegerValue = try await Interpreter.result(
      content:
        """
        << /PrinterName (Shared) /MaxOpStack 12 /SystemParamsPassword (secret) >> setsystemparams
        currentuserparams /MaxOpStack get
        """,
      environment: environment
    )
    #expect(existingDefault.value == .max)

    let futureDefault: IntegerValue = try await Interpreter.result(
      content: "currentuserparams /MaxOpStack get",
      environment: environment
    )
    #expect(futureDefault.value == 12)

    let protected: BooleanValue = try await Interpreter.result(
      content: "{ << /PrinterName (Denied) >> setsystemparams } stopped",
      environment: environment
    )
    #expect(protected.value)

    let printer: StringValue = try await Interpreter.result(
      content:
        """
        << /Password (secret) /PrinterName (Allowed) >> setsystemparams
        currentsystemparams /PrinterName get
        """,
      environment: environment
    )
    #expect(printer.nameString == "Allowed")

    let factory: BooleanValue = try await Interpreter.result(
      content: "<< /FactoryDefaults true >> setsystemparams currentsystemparams /FactoryDefaults get",
      environment: environment
    )
    #expect(factory.value)

    _ = try await Interpreter.execute(
      content: "<< /Password (secret) /MaxOpStack 100 >> setsystemparams",
      environment: environment
    )
    let normalized = try await Interpreter.results(
      content:
        """
        << /Password (secret) /PrinterName ()
           /MaxDisplayList 20 /MaxSourceList 30 /MaxDisplayAndSourceList 10
           /MaxStoredScreenCache -1 >> setsystemparams
        currentsystemparams /PrinterName get
        currentsystemparams /MaxDisplayAndSourceList get
        currentsystemparams /MaxStoredScreenCache get
        """,
      environment: environment
    )
    #expect(try normalized[0].value(as: IntegerValue.self).value == .max)
    #expect(try normalized[1].value(as: IntegerValue.self).value == 30)
    #expect(try normalized[2].value(as: StringValue.self).nameString == "SolidPostScript")
  }

  @Test
  func deviceParametersAndIODeviceResourcesUseEnvironmentRegistry() async throws {
    let device = TestParameterizedDevice()
    let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [device]))
    let value: IntegerValue = try await Interpreter.result(
      content:
        """
        (%test%) << /BufferSize 256 >> setdevparams
        (%test) currentdevparams /BufferSize get
        """,
      environment: environment
    )
    #expect(value.value == 256)

    let count: IntegerValue = try await Interpreter.result(
      content:
        """
        /deviceCount 0 def
        (*) { type /stringtype ne { stop } if /deviceCount deviceCount 1 add store } 100 string /IODevice resourceforall
        deviceCount
        """,
      environment: environment
    )
    #expect(count.value == 1)
  }

  @Test
  func sharedEnvironmentConcurrentAccess() async throws {
    let device = TestParameterizedDevice()
    let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [device]))

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<20 {
        group.addTask {
          _ = try await Interpreter.execute(
            content:
              "<< /PrinterName (Printer\(index)) >> setsystemparams (%test%) << /BufferSize \(index) >> setdevparams",
            environment: environment
          )
        }
      }
      try await group.waitForAll()
    }

    let printer: StringValue = try await Interpreter.result(
      content: "currentsystemparams /PrinterName get",
      environment: environment
    )
    #expect(printer.nameString.starts(with: "Printer"))
    let parameters = try device.currentParameters()
    #expect(try parameters["BufferSize"]?.value(as: IntegerValue.self).value != nil)
  }

  @Test
  func globalVMAccountingIsSharedWithinAnEnvironment() async throws {
    let environment = InterpreterEnvironment()
    let first = try await Interpreter.execute(
      content: "true setglobal /firstGlobal 100 string def",
      environment: environment
    )
    let firstUsage = try await first.estimatedVMUsage(in: .global)

    let second = try await Interpreter.execute(
      content: "true setglobal /secondGlobal 200 string def",
      environment: environment
    )
    let combinedUsage = try await second.estimatedVMUsage(in: .global)

    #expect(combinedUsage > firstUsage)
  }

  @Test
  func stackAndVMLimitsUseCatchableLanguageErrors() async throws {
    let stackError: NameValue = try await Interpreter.result(
      content:
        """
        /overflow { 1 2 3 4 5 } def
        << /MaxOpStack 4 >> setuserparams
        overflow stopped clear
        $error /errorname get
        """
    )
    #expect(stackError.value == "stackoverflow")

    let dictionaryError: NameValue = try await Interpreter.result(
      content:
        """
        << /MaxDictStack 3 >> setuserparams
        { 1 dict begin } stopped clear
        $error /errorname get
        """
    )
    #expect(dictionaryError.value == "dictstackoverflow")

    let executionError: NameValue = try await Interpreter.result(
      content:
        """
        /recurse { /recurse load exec } def
        << /MaxExecStack 2 >> setuserparams
        /recurse load stopped clear
        $error /errorname get
        """
    )
    #expect(executionError.value == "execstackoverflow")

    let vmError: NameValue = try await Interpreter.result(
      content:
        """
        /allocate { 10 string } def
        << /MaxLocalVM 1 >> setuserparams
        allocate stopped clear
        $error /errorname get
        """
    )
    #expect(vmError.value == "VMerror")

    let status = try await Interpreter.results(content: "vmstatus")
    #expect(status.count == 3)
    #expect(status.allSatisfy { $0.value is IntegerValue })
  }

  @Test
  func bindPerformsEnabledIdiomSubstitution() async throws {
    let substituted: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /TestIdioms << /addition [ { 1 2 add } bind { 42 } bind ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        { 1 2 add } bind exec
        """
    )
    #expect(substituted.value == 42)

    let ordinary: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /TestIdioms << /addition [ { 1 2 add } bind { 42 } bind ] >> /IdiomSet defineresource pop
        { 1 2 add } bind exec
        """
    )
    #expect(ordinary.value == 3)
  }
}

private final class TestParameterizedDevice: ParameterizedFileDevice, Sendable {
  let name = "test"
  let searched = false
  private let parameters = Mutex<[Object: Object]>([:])

  func open(name: String, mode: File.Mode, openMethod: OpenMethod) throws -> File {
    throw Error.undefinedFilename
  }

  func currentParameters() throws -> [Object: Object] {
    parameters.withLock { $0 }
  }

  func setParameters(_ parameters: [Object: Object]) throws {
    self.parameters.withLock { $0 = parameters }
  }
}
