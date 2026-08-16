import Foundation
import SolidIO
import Synchronization
@testable import SolidPostScript
import Testing

@Suite
struct HostLifecycleTests {

  @Test
  func lifecycleNamesFollowConfiguredCapabilities() async throws {
    let standalone: [NameValue] = try await Interpreter.result(
      content: "/start load type /startjob load type /executive load type /echo load type /prompt load type",
      count: 5
    )
    #expect(standalone.map(\.value) == ["arraytype", "operatortype", "operatortype", "operatortype", "arraytype"])

    let disabled = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(interactiveExecutiveEnabled: false)
    )
    let values: [BooleanValue] = try await Interpreter.result(
      content: "/executive where /echo where /prompt where /serverdict where",
      count: 4,
      environment: disabled
    )
    #expect(values.allSatisfy { !$0.value })
  }

  @Test
  func standaloneStartJobReturnsFalse() async throws {
    let result: BooleanValue = try await Interpreter.result(content: "true () startjob")
    #expect(!result.value)
  }

  @Test
  func startupRunsExactlyOncePerSession() async throws {
    let startup = RecordingStartupProvider(program: "/booted 9 def")
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(startupProgramProvider: startup)
    )
    _ = try await Interpreter.execute(
      content: "<< /StartupMode 1 >> setsystemparams",
      environment: environment
    )

    let session = InterpreterSession(environment: environment)
    async let first: Void = session.start()
    async let second: Void = session.start()
    _ = try await (first, second)
    try await session.executeJob(content: "booted 9 ne {undefined} if")

    #expect(await startup.requests == [1])
  }

  @Test
  func failedStartupIsNotRetried() async throws {
    let startup = FailingStartupProvider()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(startupProgramProvider: startup)
    )
    _ = try await Interpreter.execute(
      content: "<< /StartupMode 1 >> setsystemparams",
      environment: environment
    )
    let session = InterpreterSession(environment: environment)

    await #expect(throws: Error.ioError) { try await session.start() }
    await #expect(throws: Error.ioError) { try await session.start() }
    #expect(await startup.requestCount == 1)
  }

  @Test
  func encapsulatedJobsRollbackAndPersistentJobsRemain() async throws {
    let session = InterpreterSession()
    try await session.executeJob(content: "/temporary 1 def")
    try await session.executeJob(content: "{temporary} stopped not {undefined} if clear")

    try await session.executeJob(content: "true () startjob pop /permanent 42 def")
    try await session.executeJob(content: "permanent 42 ne {undefined} if")

    try await session.executeJob(content: "true () startjob pop /beforeSave 1 def save /afterSave 2 def")
    try await session.executeJob(
      content: "beforeSave 1 ne {undefined} if {afterSave} stopped not {undefined} if clear"
    )

    try await session.executeJob(
      content: "true () startjob pop true setglobal /shared 1 /Generic defineresource pop false setglobal"
    )
    try await session.executeJob(
      content: "true setglobal /shared 2 /Generic defineresource pop false setglobal"
    )
    try await session.executeJob(content: "/shared /Generic findresource 1 ne {undefined} if")
  }

  @Test
  func jobResetRestoresSharedAllocationModeToLocal() async throws {
    let session = InterpreterSession()
    try await session.executeJob(content: "true setshared")
    try await session.executeJob(content: "currentshared {undefined} if")
  }

  @Test
  func startJobUsesAuthorizationAndHonorsSaveDepth() async throws {
    let authorizer = RecordingAuthorizer(result: false)
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(jobAuthorizationProvider: authorizer)
    )
    let session = InterpreterSession(environment: environment)
    try await session.executeJob(content: "true (candidate) startjob {undefined} if")
    #expect(await authorizer.requests.map(\.candidate) == [Data("candidate".utf8)])

    let defaultSession = InterpreterSession()
    try await defaultSession.executeJob(content: "save true () startjob {undefined} if restore")
  }

  @Test
  func emptyPasswordsUsePLRMJobAuthorizationPrecedence() async throws {
    let defaultEnvironment = InterpreterEnvironment()
    let defaultSession = InterpreterSession(environment: defaultEnvironment)
    try await defaultSession.executeJob(
      content:
        "true (anything) startjob pop << /Password 1.5 /PrinterName (Administrator) >> setsystemparams"
    )
    let administratorName: StringValue = try await Interpreter.result(
      content: "currentsystemparams /PrinterName get",
      environment: defaultEnvironment
    )
    #expect(administratorName.nameString == "Administrator")

    let ordinaryEnvironment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (system) /StartJobPassword () >> setsystemparams",
      environment: ordinaryEnvironment
    )
    let ordinarySession = InterpreterSession(environment: ordinaryEnvironment)
    try await ordinarySession.executeJob(
      content:
        "true (anything) startjob pop { << /PrinterName (Denied) >> setsystemparams } stopped not {undefined} if clear"
    )
  }

  @Test
  func systemPasswordStartsAdministratorJobAndPrivilegeEndsWithJob() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (system) /StartJobPassword (ordinary) >> setsystemparams",
      environment: environment
    )
    let session = InterpreterSession(environment: environment)

    try await session.executeJob(
      content: "true (system) startjob pop << /PrinterName (Authorized) >> setsystemparams"
    )
    let printerName: StringValue = try await Interpreter.result(
      content: "currentsystemparams /PrinterName get",
      environment: environment
    )
    #expect(printerName.nameString == "Authorized")

    try await session.executeJob(
      content:
        "{ << /PrinterName (Leaked) >> setsystemparams } stopped not {undefined} if clear"
    )
    let unchanged: StringValue = try await Interpreter.result(
      content: "currentsystemparams /PrinterName get",
      environment: environment
    )
    #expect(unchanged.nameString == "Authorized")
  }

  @Test
  func passwordsPreserveAllBytesAndUseDecimalIntegerConversion() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (sys\000tail) /StartJobPassword -42 >> setsystemparams",
      environment: environment
    )
    let session = InterpreterSession(environment: environment)

    try await session.executeJob(
      content: "true (sys\000) startjob {undefined} if true (SYS\000tail) startjob {undefined} if"
    )
    try await session.executeJob(
      content:
        "true -42 startjob pop $error /recordstacks false put { << /PrinterName (Denied) >> setsystemparams } stopped clear"
    )
    try await session.executeJob(
      content: "true (sys\000tail) startjob pop << /PrinterName (Exact) >> setsystemparams"
    )
  }

  @Test
  func authorizationOutcomeProvidersCanGrantAdministratorJobs() async throws {
    let legacyEnvironment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        jobAuthorizationProvider: RecordingAuthorizer(result: true)
      )
    )
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (protected) >> setsystemparams",
      environment: legacyEnvironment
    )
    let legacySession = InterpreterSession(environment: legacyEnvironment)
    try await legacySession.executeJob(
      content:
        "true (ignored) startjob pop { << /PrinterName (Denied) >> setsystemparams } stopped not {undefined} if clear"
    )

    let outcomeProvider = RecordingOutcomeAuthorizer(outcome: .administrator)
    let outcomeEnvironment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(jobAuthorizationProvider: outcomeProvider)
    )
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (protected) >> setsystemparams",
      environment: outcomeEnvironment
    )
    let outcomeSession = InterpreterSession(environment: outcomeEnvironment)
    try await outcomeSession.executeJob(
      content: "true (ignored) startjob pop << /PrinterName (Granted) >> setsystemparams"
    )
    #expect(await outcomeProvider.requests.count == 1)
  }

  @Test
  func administratorPrivilegeControlsDeviceParameters() async throws {
    let device = LifecycleParameterizedDevice()
    let environment = InterpreterEnvironment(fileDevices: FileDevices(devices: [device]))
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (system) /StartJobPassword (ordinary) >> setsystemparams",
      environment: environment
    )
    let session = InterpreterSession(environment: environment)

    try await session.executeJob(
      content:
        "true (ordinary) startjob pop $error /recordstacks false put { (%lifecycle%) << /Value 1 >> setdevparams } stopped not {undefined} if clear"
    )
    #expect(try device.value() == nil)

    try await session.executeJob(
      content: "true (system) startjob pop (%lifecycle%) << /Value 2 >> setdevparams"
    )
    #expect(try device.value() == 2)

    try await session.executeJob(
      content:
        "$error /recordstacks false put { (%lifecycle%) << /Value 3 >> setdevparams } stopped not {undefined} if clear"
    )
    #expect(try device.value() == 2)
  }

  @Test
  func serverDictionaryAndExitServerUseJobLifecycle() async throws {
    let session = InterpreterSession()
    try await session.executeJob(
      content: "serverdict type /dicttype ne {undefined} if serverdict begin () exitserver /installed true def"
    )
    try await session.executeJob(content: "installed not {undefined} if")
  }

  @Test
  func exitServerUsesTheSameEmptyPasswordAuthorizationOutcomes() async throws {
    let administratorEnvironment = InterpreterEnvironment()
    let administratorSession = InterpreterSession(environment: administratorEnvironment)
    try await administratorSession.executeJob(
      content:
        """
        serverdict begin (anything) exitserver
        << /SystemParamsPassword (protected) >> setsystemparams
        << /PrinterName (Administrator) >> setsystemparams
        """
    )
    let administratorName: StringValue = try await Interpreter.result(
      content: "currentsystemparams /PrinterName get",
      environment: administratorEnvironment
    )
    #expect(administratorName.nameString == "Administrator")

    let ordinaryEnvironment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "<< /SystemParamsPassword (protected) /StartJobPassword () >> setsystemparams",
      environment: ordinaryEnvironment
    )
    let ordinarySession = InterpreterSession(environment: ordinaryEnvironment)
    try await ordinarySession.executeJob(
      content:
        """
        serverdict begin (anything) exitserver
        $error /recordstacks false put
        { << /PrinterName (Denied) >> setsystemparams } stopped not {undefined} if clear
        """
    )
  }

  @Test
  func executiveUsesConfiguredOutputEchoAndPrompt() async throws {
    let provider = QueueExecutiveProvider(events: [.data(Data("1 2 add =\n".utf8)), .endOfFile])
    let output = DataSink()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardOutput: output,
        interactiveExecutiveProvider: provider
      )
    )

    _ = try await Interpreter.execute(content: "executive", environment: environment)
    #expect(String(data: output.data, encoding: .isoLatin1) == "PS>1 2 add =\n3\nPS>")
  }

  @Test
  func executivePromptCanBeOverriddenAndEchoDisabled() async throws {
    let provider = QueueExecutiveProvider(events: [.data(Data("(ok) =\n".utf8)), .endOfFile])
    let output = DataSink()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardOutput: output,
        interactiveExecutiveProvider: provider
      )
    )

    _ = try await Interpreter.execute(
      content: "/prompt {(X) print} def false echo executive",
      environment: environment
    )
    #expect(String(data: output.data, encoding: .isoLatin1) == "Xok\nX")
  }

  @Test
  func executiveRecoversAfterErrorsAndInterrupts() async throws {
    let provider = QueueExecutiveProvider(
      events: [
        .data(Data("doesnotexist\n".utf8)),
        .interrupt,
        .data(Data("(recovered) =\n".utf8)),
        .endOfFile,
      ]
    )
    let output = DataSink()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardOutput: output,
        interactiveExecutiveProvider: provider
      )
    )

    _ = try await Interpreter.execute(content: "false echo executive", environment: environment)
    #expect(String(data: output.data, encoding: .isoLatin1)?.contains("recovered\n") == true)
  }

  @Test
  func editingFilesBufferLinesAndCompleteStatements() async throws {
    let lineProvider = QueueExecutiveProvider(events: [.data(Data([0x61, 0x62, 0x08, 0x63, 0x0A]))])
    let lineEnvironment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(interactiveExecutiveProvider: lineProvider)
    )
    let line: StringValue = try await Interpreter.result(
      content: "(%lineedit) (r) file 10 string readline pop",
      environment: lineEnvironment
    )
    #expect(line.string == "ac")

    let statementProvider = QueueExecutiveProvider(events: [.data(Data("{1\n2 add}\n".utf8))])
    let statementEnvironment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardOutput: DataSink(),
        interactiveExecutiveProvider: statementProvider
      )
    )
    let available: IntegerValue = try await Interpreter.result(
      content: "(%statementedit) (r) file bytesavailable",
      environment: statementEnvironment
    )
    #expect(available.value == 10)

    for statement in ["<< /a\n1 >>\n", "<4142\n43>\n", "<~87cU\nR~>\n"] {
      let provider = QueueExecutiveProvider(
        events: statement.split(separator: "\n").map {
          .data(Data((String($0) + "\n").utf8))
        }
      )
      let environment = InterpreterEnvironment(
        hostConfiguration: InterpreterHostConfiguration(
          standardOutput: DataSink(),
          interactiveExecutiveProvider: provider
        )
      )
      let value: IntegerValue = try await Interpreter.result(
        content: "(%statementedit) (r) file bytesavailable",
        environment: environment
      )
      #expect(value.value == Int32(statement.utf8.count))
    }
  }

  @Test
  func jobServerQuitIsMaskedAndSystemQuitRequiresPersistentJob() async throws {
    let session = InterpreterSession()
    try await session.executeJob(content: "quit /unreachable true def")
    try await session.executeJob(content: "{unreachable} stopped not {undefined} if clear")

    await #expect(throws: Error.invalidAccess) {
      try await session.executeJob(content: "systemdict /quit get exec")
    }
  }

  @Test
  func standardInputCanBeExecutedThroughTheAsyncSource() async throws {
    let output = DataSink()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardInput: DataSource(data: Data("(from stdin) =".utf8)),
        standardOutput: output
      )
    )
    _ = try await Interpreter.execute(
      content: "(%stdin) (r) file cvx exec",
      environment: environment
    )
    #expect(String(data: output.data, encoding: .isoLatin1) == "from stdin\n")
  }

  @Test
  func standardFilesUseConfiguredStreamsAndJobIdentity() async throws {
    let output = DataSink()
    let error = DataSink()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardInput: DataSource(data: Data("A".utf8)),
        standardOutput: output,
        standardError: error
      )
    )

    _ = try await Interpreter.execute(
      content:
        "(%stdout) (w) file (%stdout) (w) file eq = (%stdin) (r) file read exch pop = (%stderr) (w) file (E) writestring",
      environment: environment
    )
    #expect(String(data: output.data, encoding: .isoLatin1) == "true\n65\n")
    #expect(error.data == Data("E".utf8))

    let invalidMode: BooleanValue = try await Interpreter.result(
      content: "{(%stdout) (r) file} stopped",
      environment: environment
    )
    #expect(invalidMode.value)
  }

  @Test
  func lifecycleNoticesUseTheExistingOrderedOutputChannel() async throws {
    let output = DataSink()
    let observer = NoticeObserver()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardOutput: output,
        lifecycleObserver: observer
      )
    )
    let session = InterpreterSession(environment: environment)

    try await session.executeJob(content: "(P) print")
    #expect(String(data: output.data, encoding: .isoLatin1) == "SJPF")

    let exitOutput = DataSink()
    let exitObserver = ExitNoticeObserver()
    let exitEnvironment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardOutput: exitOutput,
        lifecycleObserver: exitObserver
      )
    )
    let exitSession = InterpreterSession(environment: exitEnvironment)
    try await exitSession.executeJob(
      content: "$error /binary true put serverdict begin () exitserver"
    )
    #expect(exitOutput.data.isEmpty)
  }
}

private actor RecordingStartupProvider: StartupProgramProvider {
  private let program: Data
  private(set) var requests: [Int32] = []

  init(program: String) {
    self.program = Data(program.utf8)
  }

  func startupProgram(for mode: Int32) async throws -> Data? {
    requests.append(mode)
    return program
  }
}

private actor FailingStartupProvider: StartupProgramProvider {
  private(set) var requestCount = 0

  func startupProgram(for mode: Int32) async throws -> Data? {
    requestCount += 1
    throw CocoaError(.fileReadUnknown)
  }
}

private actor RecordingAuthorizer: JobAuthorizationProvider {
  private let result: Bool
  private(set) var requests: [JobAuthorizationRequest] = []

  init(result: Bool) {
    self.result = result
  }

  func authorize(_ request: JobAuthorizationRequest) async throws -> Bool {
    requests.append(request)
    return result
  }
}

private actor RecordingOutcomeAuthorizer: JobAuthorizationOutcomeProvider {
  private let outcome: JobAuthorizationOutcome
  private(set) var requests: [JobAuthorizationRequest] = []

  init(outcome: JobAuthorizationOutcome) {
    self.outcome = outcome
  }

  func authorizationOutcome(for request: JobAuthorizationRequest) async throws -> JobAuthorizationOutcome {
    requests.append(request)
    return outcome
  }
}

private final class LifecycleParameterizedDevice: ParameterizedFileDevice, Sendable {
  let name = "lifecycle"
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

  func value() throws -> Int32? {
    try parameters.withLock { parameters in
      try parameters["Value"]?.value(as: IntegerValue.self).value
    }
  }
}

private actor QueueExecutiveProvider: InteractiveExecutiveProvider {
  private var events: [InteractiveExecutiveEvent]

  init(events: [InteractiveExecutiveEvent]) {
    self.events = events
  }

  func nextEvent() async throws -> InteractiveExecutiveEvent {
    events.isEmpty ? .endOfFile : events.removeFirst()
  }
}

private struct NoticeObserver: InterpreterLifecycleObserver {
  func interpreter(didEmit event: InterpreterLifecycleEvent) async {}

  func notice(for event: InterpreterLifecycleEvent) async -> Data? {
    switch event {
    case .started: Data("S".utf8)
    case .jobStarted: Data("J".utf8)
    case .jobFinished: Data("F".utf8)
    case .exitServerAuthorized: Data("X".utf8)
    case .error: Data("E".utf8)
    }
  }
}

private struct ExitNoticeObserver: InterpreterLifecycleObserver {
  func interpreter(didEmit event: InterpreterLifecycleEvent) async {}

  func notice(for event: InterpreterLifecycleEvent) async -> Data? {
    if case .exitServerAuthorized = event { Data("X".utf8) } else { nil }
  }
}
