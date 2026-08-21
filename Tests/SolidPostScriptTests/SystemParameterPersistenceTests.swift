import Foundation
import Testing

@testable import SolidPostScript

@Suite
struct SystemParameterPersistenceTests {

  @Test
  func processLocalStoreUsesGenerationCompareAndReplace() throws {
    let store = ProcessLocalSystemParameterStore()
    let first = PostScriptSystemParameterRecord(generation: 1, opaquePayload: Data([1]))
    let second = PostScriptSystemParameterRecord(generation: 2, opaquePayload: Data([2]))

    #expect(store.compareAndReplace(expectedGeneration: nil, with: first))
    #expect(!store.compareAndReplace(expectedGeneration: nil, with: first))
    #expect(!store.compareAndReplace(expectedGeneration: 0, with: second))
    #expect(store.compareAndReplace(expectedGeneration: 1, with: second))
    #expect(store.load() == second)
  }

  @Test
  func mutableParametersDefaultsAndPasswordsPersistAcrossPowerCycles() async throws {
    let store = ProcessLocalSystemParameterStore()
    let configuration = InterpreterHostConfiguration(systemParameterStore: store)
    let first = InterpreterEnvironment(hostConfiguration: configuration)
    _ = try await Interpreter.execute(
      content:
        """
        << /PrinterName (Persistent)
           /MaxOutlineCache 1234
           /MaxOpStack 456
           /SystemParamsPassword (secret) >> setsystemparams
        """,
      environment: first
    )

    let second = InterpreterEnvironment(hostConfiguration: configuration)
    let values = try await Interpreter.results(
      content:
        """
        currentsystemparams /PrinterName get
        currentsystemparams /MaxOutlineCache get
        currentuserparams /MaxOpStack get
        """,
      environment: second
    )
    #expect(try values[2].value(as: StringValue.self).nameString == "Persistent")
    #expect(try values[1].value(as: IntegerValue.self).value == 1234)
    #expect(try values[0].value(as: IntegerValue.self).value == 456)

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(
        content: "<< /PrinterName (Denied) >> setsystemparams",
        environment: second
      )
    }
    _ = try await Interpreter.execute(
      content: "<< /Password (secret) /PrinterName (Allowed) >> setsystemparams",
      environment: second
    )
  }

  @Test
  func factoryDefaultsRemainArmedAfterSettingJobAndApplyAtNextPowerOn() async throws {
    let store = ProcessLocalSystemParameterStore()
    let configuration = InterpreterHostConfiguration(systemParameterStore: store)
    let first = InterpreterEnvironment(hostConfiguration: configuration)
    _ = try await Interpreter.execute(
      content: "<< /PrinterName (Changed) /FactoryDefaults true >> setsystemparams",
      environment: first
    )

    let armedRecord = try #require(store.load())
    let armedState = try #require(SystemParameterPersistence.decode(armedRecord.opaquePayload))
    #expect(armedState.values["FactoryDefaults"] == .boolean(true))

    let poweredOn = InterpreterEnvironment(hostConfiguration: configuration)
    let values = try await Interpreter.results(
      content:
        """
        currentsystemparams /PrinterName get
        currentsystemparams /FactoryDefaults get
        """,
      environment: poweredOn
    )
    #expect(try values[1].value(as: StringValue.self).nameString == PostScriptProduct.name)
    #expect(try values[0].value(as: BooleanValue.self).value == false)
  }

  @Test
  func laterJobDisarmsFactoryDefaultsWithoutResettingValues() async throws {
    let store = ProcessLocalSystemParameterStore()
    let configuration = InterpreterHostConfiguration(systemParameterStore: store)
    let environment = InterpreterEnvironment(hostConfiguration: configuration)
    _ = try await Interpreter.execute(
      content: "<< /PrinterName (Retained) /FactoryDefaults true >> setsystemparams",
      environment: environment
    )
    _ = try await Interpreter.execute(content: "", environment: environment)

    let poweredOn = InterpreterEnvironment(hostConfiguration: configuration)
    let values = try await Interpreter.results(
      content:
        """
        currentsystemparams /PrinterName get
        currentsystemparams /FactoryDefaults get
        """,
      environment: poweredOn
    )
    #expect(try values[1].value(as: StringValue.self).nameString == "Retained")
    #expect(try values[0].value(as: BooleanValue.self).value == false)
  }

  @Test
  func concurrentJobActivityDisarmsAnotherJobsFactoryReset() throws {
    let store = ProcessLocalSystemParameterStore()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(systemParameterStore: store)
    )
    let settingJob = environment.beginPersistentJob()
    let concurrentJob = environment.beginPersistentJob()
    try environment.updateSystemParameters(
      from: DictionaryValue(
        value: [.literalName("FactoryDefaults"): .boolean(true)],
        access: .unlimited,
        vm: .local
      ),
      jobToken: settingJob
    )

    environment.finishPersistentJob(settingJob)
    let armed = try #require(store.load())
    #expect(SystemParameterPersistence.decode(armed.opaquePayload)?.values["FactoryDefaults"] == .boolean(true))
    environment.finishPersistentJob(concurrentJob)
    let disarmed = try #require(store.load())
    #expect(SystemParameterPersistence.decode(disarmed.opaquePayload)?.values["FactoryDefaults"] == .boolean(false))
  }

  @Test
  func persistenceFailureLeavesValidatedUpdateActiveInCurrentEnvironment() async throws {
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(systemParameterStore: FailingSystemParameterStore())
    )
    _ = try await Interpreter.execute(
      content: "<< /PrinterName (Volatile) >> setsystemparams",
      environment: environment
    )
    let printer: StringValue = try await Interpreter.result(
      content: "currentsystemparams /PrinterName get",
      environment: environment
    )
    #expect(printer.nameString == "Volatile")
  }

  @Test
  func factoryResetPreservesPageCountAndRejectsMalformedRecords() async throws {
    let pageStore = ProcessLocalSystemParameterStore()
    var state = SystemParameterState()
    state.values["PageCount"] = .integer(42)
    state.values["FactoryDefaults"] = .boolean(true)
    let payload = try SystemParameterPersistence.encode(state)
    #expect(pageStore.compareAndReplace(
      expectedGeneration: nil,
      with: PostScriptSystemParameterRecord(generation: 1, opaquePayload: payload)
    ))
    let pageEnvironment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(systemParameterStore: pageStore)
    )
    let pageCount: IntegerValue = try await Interpreter.result(
      content: "currentsystemparams /PageCount get",
      environment: pageEnvironment
    )
    #expect(pageCount.value == 42)

    let malformedStore = ProcessLocalSystemParameterStore()
    #expect(malformedStore.compareAndReplace(
      expectedGeneration: nil,
      with: PostScriptSystemParameterRecord(generation: 1, opaquePayload: Data("invalid".utf8))
    ))
    let malformedEnvironment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(systemParameterStore: malformedStore)
    )
    let printer: StringValue = try await Interpreter.result(
      content: "currentsystemparams /PrinterName get",
      environment: malformedEnvironment
    )
    #expect(printer.nameString == PostScriptProduct.name)
  }

  @Test
  func languageAndSystemParameterRevisionsMatch() async throws {
    let values = try await Interpreter.results(
      content: "revision currentsystemparams /Revision get eq revision"
    )
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: IntegerValue.self).value == PostScriptProduct.revision)
  }
}

private struct FailingSystemParameterStore: PostScriptSystemParameterStore {
  struct Failure: Swift.Error {}

  func load() throws -> PostScriptSystemParameterRecord? { throw Failure() }

  func compareAndReplace(
    expectedGeneration: UInt64?,
    with record: PostScriptSystemParameterRecord
  ) throws -> Bool {
    throw Failure()
  }
}
