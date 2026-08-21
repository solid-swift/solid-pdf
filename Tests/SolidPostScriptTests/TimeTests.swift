//
//  TimeTests.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation
import SolidIO
import SolidTempo
import Synchronization
@testable import SolidPostScript
import Testing

@Suite
struct TimeTests {

  @Test
  func realtimeUsesTheEnvironmentMonotonicSource() async throws {
    let source = ManualInstantSource(instant: Instant(durationSinceEpoch: .milliseconds(1_234)))
    let environment = InterpreterEnvironment(monotonicInstantSource: source)

    let first: IntegerValue = try await Interpreter.result(content: "realtime", environment: environment)
    try source.advance(by: .milliseconds(9))
    let second: IntegerValue = try await Interpreter.result(content: "realtime", environment: environment)

    #expect(first.value == 1_234)
    #expect(second.value == 1_243)
  }

  @Test
  func usertimeCountsOnlyActiveExecution() async throws {
    let source = ManualInstantSource()
    let context = Context(environment: InterpreterEnvironment(monotonicInstantSource: source))

    let first = try await context.executeForTimeTesting(
      content: "advancetime usertime",
      source: source,
      duration: .milliseconds(750)
    )
    try source.advance(by: .seconds(30))
    let second = try await context.executeForTimeTesting(
      content: "advancetime usertime",
      source: source,
      duration: .milliseconds(250)
    )

    #expect(try first[0].value(as: IntegerValue.self).value == 750)
    #expect(try second[0].value(as: IntegerValue.self).value == 1_000)
  }

  @Test
  func nestedExecutionAndSuspensionScopesBalance() async throws {
    let source = ManualInstantSource()
    let context = Context(environment: InterpreterEnvironment(monotonicInstantSource: source))

    try await context.withUserTimeAccounting {
      try source.advance(by: .milliseconds(100))
      try await context.withUserTimeAccounting {
        try source.advance(by: .milliseconds(200))
        try await context.withUserTimeSuspended {
          try source.advance(by: .seconds(10))
          try await context.withUserTimeSuspended {
            try source.advance(by: .seconds(10))
          }
        }
      }
      try source.advance(by: .milliseconds(300))
    }

    let stopwatch = await context.userTime
    #expect(stopwatch.elapsed[.totalMilliseconds] == 600)
    #expect(!stopwatch.isRunning)
  }

  @Test
  func failedExecutionLeavesTheStopwatchBalanced() async throws {
    let source = ManualInstantSource()
    let context = Context(environment: InterpreterEnvironment(monotonicInstantSource: source))

    await #expect(throws: TimingFailure.self) {
      try await context.withUserTimeAccounting {
        try source.advance(by: .milliseconds(10))
        throw TimingFailure.expected
      }
    }
    await #expect(throws: CancellationError.self) {
      try await context.withUserTimeAccounting {
        try source.advance(by: .milliseconds(5))
        throw CancellationError()
      }
    }
    try source.advance(by: .seconds(10))
    try await context.withUserTimeAccounting {
      try source.advance(by: .milliseconds(15))
    }

    let stopwatch = await context.userTime
    #expect(stopwatch.elapsed[.totalMilliseconds] == 30)
    #expect(!stopwatch.isRunning)
  }

  @Test
  func subMillisecondExecutionCarriesAcrossEntries() async throws {
    let source = ManualInstantSource()
    let context = Context(environment: InterpreterEnvironment(monotonicInstantSource: source))

    _ = try await context.executeForTimeTesting(
      content: "advancetime",
      source: source,
      duration: .microseconds(500)
    )
    let results = try await context.executeForTimeTesting(
      content: "advancetime usertime",
      source: source,
      duration: .microseconds(500)
    )

    #expect(try results[0].value(as: IntegerValue.self).value == 1)
  }

  @Test
  func standardOutputWaitIsExcluded() async throws {
    let source = ManualInstantSource()
    let sink = AdvancingSink(source: source, duration: .seconds(10))
    let host = InterpreterHostConfiguration(standardOutput: sink)
    let environment = InterpreterEnvironment(hostConfiguration: host, monotonicInstantSource: source)
    let context = Context(environment: environment)

    let results = try await context.executeForTimeTesting(
      content: "advancetime (output) print usertime",
      source: source,
      duration: .milliseconds(25)
    )

    #expect(try results[0].value(as: IntegerValue.self).value == 25)
    #expect(sink.data == Data("output".utf8))
  }

  @Test
  func standardInputAndExecutiveWaitsAreExcluded() async throws {
    let inputSource = ManualInstantSource()
    let input = AdvancingSource(
      data: Data("A".utf8),
      source: inputSource,
      duration: .seconds(10)
    )
    let inputHost = InterpreterHostConfiguration(standardInput: input)
    let inputEnvironment = InterpreterEnvironment(
      hostConfiguration: inputHost,
      monotonicInstantSource: inputSource
    )
    let inputTime: IntegerValue = try await Interpreter.result(
      content: "(%stdin) (r) file read pop pop usertime",
      environment: inputEnvironment
    )

    let executiveSource = ManualInstantSource()
    let executive = AdvancingExecutiveProvider(source: executiveSource, duration: .seconds(10))
    let executiveHost = InterpreterHostConfiguration(
      standardOutput: DataSink(),
      interactiveExecutiveProvider: executive
    )
    let executiveEnvironment = InterpreterEnvironment(
      hostConfiguration: executiveHost,
      monotonicInstantSource: executiveSource
    )
    let executiveTime: IntegerValue = try await Interpreter.result(
      content: "executive usertime",
      environment: executiveEnvironment
    )

    #expect(inputTime.value == 0)
    #expect(executiveTime.value == 0)
  }

  @Test
  func startupAuthorizationAndLifecycleWaitsAreExcluded() async throws {
    let startupSource = ManualInstantSource()
    let startup = AdvancingStartupProvider(source: startupSource, duration: .seconds(10))
    let startupHost = InterpreterHostConfiguration(startupProgramProvider: startup)
    let startupEnvironment = InterpreterEnvironment(
      hostConfiguration: startupHost,
      monotonicInstantSource: startupSource
    )
    _ = try await Interpreter.execute(
      content: "<< /StartupMode 1 >> setsystemparams",
      environment: startupEnvironment
    )
    let startupContext = Context(environment: startupEnvironment)
    try await startupContext.executeStart()
    let startupStopwatch = await startupContext.userTime

    let jobSource = ManualInstantSource()
    let authorizer = AdvancingAuthorizer(source: jobSource, duration: .seconds(10))
    let observer = AdvancingLifecycleObserver(source: jobSource, duration: .seconds(10))
    let jobHost = InterpreterHostConfiguration(
      jobAuthorizationProvider: authorizer,
      lifecycleObserver: observer
    )
    let jobEnvironment = InterpreterEnvironment(
      hostConfiguration: jobHost,
      monotonicInstantSource: jobSource
    )
    let session = InterpreterSession(environment: jobEnvironment)
    let jobContext = try await session.executeJob(content: "false () startjob pop")
    let jobStopwatch = await jobContext.userTime

    #expect(startupStopwatch.elapsed == .zero)
    #expect(jobStopwatch.elapsed == .zero)
  }

  @Test
  func contextsSharingAnEnvironmentKeepIndependentUsertime() async throws {
    let source = ManualInstantSource()
    let environment = InterpreterEnvironment(monotonicInstantSource: source)
    let first = Context(environment: environment)
    let second = Context(environment: environment)

    let firstResults = try await first.executeForTimeTesting(
      content: "advancetime usertime",
      source: source,
      duration: .milliseconds(10)
    )
    let secondResults = try await second.executeForTimeTesting(
      content: "advancetime usertime",
      source: source,
      duration: .milliseconds(20)
    )

    #expect(try firstResults[0].value(as: IntegerValue.self).value == 10)
    #expect(try secondResults[0].value(as: IntegerValue.self).value == 20)
  }

  @Test
  func timeOperatorsUseSigned32BitWraparound() async throws {
    let wrapDuration = SolidTempo.Duration.milliseconds(Int64(Int32.max) + 1)
    let realtimeSource = ManualInstantSource(instant: Instant(durationSinceEpoch: wrapDuration))
    let realtimeEnvironment = InterpreterEnvironment(monotonicInstantSource: realtimeSource)
    let realtime: IntegerValue = try await Interpreter.result(
      content: "realtime",
      environment: realtimeEnvironment
    )

    let usertimeSource = ManualInstantSource()
    let context = Context(environment: InterpreterEnvironment(monotonicInstantSource: usertimeSource))
    let results = try await context.executeForTimeTesting(
      content: "advancetime usertime",
      source: usertimeSource,
      duration: .milliseconds(Int64(Int32.max) + 1)
    )

    #expect(realtime.value == Int32.min)
    #expect(try results[0].value(as: IntegerValue.self).value == Int32.min)
  }
}

private enum TimingFailure: Swift.Error {
  case expected
}

// Keep the test operator's timing value scalar across the Context actor boundary. Swift 6.3 on
// Linux/ARM64 corrupts the upper word when the Int128-backed SolidTempo.Duration is stored there.
private struct TestDuration: Sendable {
  let nanoseconds: Int64

  static func milliseconds(_ value: Int64) -> Self {
    Self(nanoseconds: value * 1_000_000)
  }

  static func microseconds(_ value: Int64) -> Self {
    Self(nanoseconds: value * 1_000)
  }
}

private struct AdvanceTimeOperator: OperatorValue {
  static let systemDictionaryNames: [Object] = ["advancetime"]

  let source: ManualInstantSource
  let durationNanoseconds: Int64

  func execute(context: isolated Context) async throws {
    try source.advance(by: .nanoseconds(durationNanoseconds))
  }

  func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else { return false }
    return source === other.source && durationNanoseconds == other.durationNanoseconds
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(source))
    hasher.combine(durationNanoseconds)
  }
}

private final class AdvancingSink: Sink, Sendable {
  private let state = Mutex(Data())
  private let source: ManualInstantSource
  private let duration: SolidTempo.Duration

  var data: Data { state.withLock { $0 } }
  var bytesWritten: Int { state.withLock(\.count) }

  init(source: ManualInstantSource, duration: SolidTempo.Duration) {
    self.source = source
    self.duration = duration
  }

  func write(data: Data) throws {
    try source.advance(by: duration)
    state.withLock { $0.append(data) }
  }

  func close() {}
}

private final class AdvancingSource: Source, Sendable {
  private struct State: Sendable {
    var data: Data
    var bytesRead = 0
  }

  private let state: Mutex<State>
  private let source: ManualInstantSource
  private let duration: SolidTempo.Duration

  var bytesRead: Int { state.withLock(\.bytesRead) }

  init(data: Data, source: ManualInstantSource, duration: SolidTempo.Duration) {
    self.state = Mutex(State(data: data))
    self.source = source
    self.duration = duration
  }

  func read(max: Int) throws -> Data? {
    try source.advance(by: duration)
    return state.withLock { state in
      guard !state.data.isEmpty else { return nil }
      let count = min(max, state.data.count)
      let result = Data(state.data.prefix(count))
      state.data.removeFirst(count)
      state.bytesRead += count
      return result
    }
  }

  func close() {}
}

private struct AdvancingStartupProvider: StartupProgramProvider {
  let source: ManualInstantSource
  let duration: SolidTempo.Duration

  func startupProgram(for mode: Int32) async throws -> Data? {
    try source.advance(by: duration)
    return nil
  }
}

private struct AdvancingAuthorizer: JobAuthorizationProvider {
  let source: ManualInstantSource
  let duration: SolidTempo.Duration

  func authorize(_ request: JobAuthorizationRequest) async throws -> Bool {
    try source.advance(by: duration)
    return true
  }
}

private struct AdvancingLifecycleObserver: InterpreterLifecycleObserver {
  let source: ManualInstantSource
  let duration: SolidTempo.Duration

  func interpreter(didEmit event: InterpreterLifecycleEvent) async {
    try? source.advance(by: duration)
  }
}

private actor AdvancingExecutiveProvider: InteractiveExecutiveProvider {
  let source: ManualInstantSource
  let duration: SolidTempo.Duration

  init(source: ManualInstantSource, duration: SolidTempo.Duration) {
    self.source = source
    self.duration = duration
  }

  func nextEvent() async throws -> InteractiveExecutiveEvent {
    try source.advance(by: duration)
    return .endOfFile
  }
}

private extension Context {
  func executeForTimeTesting(
    content: String,
    source: ManualInstantSource,
    duration: TestDuration
  ) async throws -> [Object] {
    let advance = AdvanceTimeOperator(source: source, durationNanoseconds: duration.nanoseconds)
    try dictionaries.userDictionary().updateObject(.init(value: advance), forKey: "advancetime")
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
