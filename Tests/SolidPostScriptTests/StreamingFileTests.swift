import Foundation
import SolidIO
import Synchronization
@testable import SolidPostScript
import Testing

@Suite
struct StreamingFileTests {

  @Test(.timeLimit(.minutes(1)))
  func standardInputExecutesTokensBeforeEndOfFile() async throws {
    let input = StreamingSource()
    let output = WaitingSink()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardInput: input,
        standardOutput: output
      )
    )
    let execution = Task {
      try await Interpreter.execute(
        content: "(%stdin) (r) file cvx exec",
        environment: environment
      )
    }

    input.send(Data("(early) print flush ".utf8))
    await output.waitForBytes(count: 5)
    #expect(await output.data == Data("early".utf8))

    input.finish()
    _ = try await execution.value
  }

  @Test(.timeLimit(.minutes(1)))
  func standardInputScansNestedProceduresAcrossChunks() async throws {
    let input = StreamingSource()
    let output = WaitingSink()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardInput: input,
        standardOutput: output
      )
    )
    let execution = Task {
      try await Interpreter.execute(
        content: "(%stdin) (r) file cvx exec",
        environment: environment
      )
    }

    input.send(Data("{1 {".utf8))
    await input.waitUntilReadStarted()
    input.send(Data("2} 3} length == flush".utf8))
    await output.waitForBytes(count: 2)
    #expect(await output.data == Data("3\n".utf8))

    input.finish()
    _ = try await execution.value
  }

  @Test(.timeLimit(.minutes(1)))
  func readStringCombinesPartialLiveInputChunks() async throws {
    let input = StreamingSource()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(standardInput: input)
    )
    let execution = Task {
      try await Interpreter.results(
        content: "(%stdin) (r) file 3 string readstring",
        environment: environment
      )
    }

    await input.waitUntilReadStarted()
    input.send(Data("A".utf8))
    input.send(Data("B".utf8))
    input.send(Data("C".utf8))

    let results = try await execution.value
    #expect(try results[0].value(as: BooleanValue.self).value)
    #expect(try results[1].value(as: StringValue.self).string == "ABC")
    #expect(input.bytesRead == 3)
    input.finish()
  }

  @Test
  func fileTokenReturnsACompleteProcedure() async throws {
    let results = try await Interpreter.results(
      content: "(%stdin) (r) file token",
      environment: environment(standardInput: Data("{1 {2} 3}".utf8))
    )

    #expect(try results[0].value(as: BooleanValue.self).value)
    let procedure = try results[1].value(as: ArrayValue.self)
    #expect(procedure.count == 3)
    #expect(try procedure.object(at: 1).value(as: ArrayValue.self).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellationStopsAPendingStandardInputRead() async throws {
    let input = StreamingSource()
    let environment = InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(standardInput: input)
    )
    let execution = Task {
      try await Interpreter.execute(
        content: "(%stdin) (r) file cvx exec",
        environment: environment
      )
    }

    await input.waitUntilReadStarted()
    execution.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await execution.value
    }
  }

  @Test
  func currentFilePreservesStandardInputIdentity() async throws {
    let environment = environment(standardInput: Data("currentfile (%stdin) (r) file eq".utf8))
    let result: BooleanValue = try await Interpreter.result(
      content: "(%stdin) (r) file cvx exec",
      environment: environment
    )
    #expect(result.value)
  }

  @Test
  func standardInputCursorContinuesAcrossRestore() async throws {
    let results = try await Interpreter.results(
      content:
        """
        (%stdin) (r) file
        dup read pop pop
        save /s exch def
        (%stdin) (r) file
        dup read pop pop
        s restore
        read
        """,
      environment: environment(standardInput: Data("ABC".utf8))
    )

    #expect(try results[0].value(as: IntegerValue.self).value == 67)
    #expect(try results[1].value(as: BooleanValue.self).value)
    let file = try results[2].value(as: FileValue.self)
    #expect(!file.file.isClosed)
  }

  @Test
  func contextualScannerConsumesOneCompleteWhitespaceSeparator() async throws {
    for separator in [" ", "\n", "\r", "\r\n"] {
      let environment = environment(standardInput: Data("currentfile read\(separator)x".utf8))
      let results = try await Interpreter.results(
        content: "(%stdin) (r) file cvx exec",
        environment: environment
      )
      #expect(try results[0].value(as: IntegerValue.self).value == 120)
      #expect(try results[1].value(as: BooleanValue.self).value)
    }
  }

  @Test
  func contextualScannerLeavesDelimitersUnread() async throws {
    let environment = environment(standardInput: Data("currentfile read<".utf8))
    let results = try await Interpreter.results(
      content: "(%stdin) (r) file cvx exec",
      environment: environment
    )

    #expect(try results[0].value(as: IntegerValue.self).value == 60)
    #expect(try results[1].value(as: BooleanValue.self).value)
  }

  @Test
  func fileOperatorsShareScannerLookaheadAcrossAliases() async throws {
    let file = DataFile(data: Data("123<".utf8), mode: .read)
    let environment = environment(file: file)
    let results = try await Interpreter.results(
      content: """
        /file (%cursor%input) (r) file def
        /alias file def
        file token pop pop
        alias fileposition
        alias bytesavailable
        alias read
        """,
      environment: environment
    )

    #expect(try results[0].value(as: IntegerValue.self).value == 60)
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: IntegerValue.self).value == 1)
    #expect(try results[3].value(as: IntegerValue.self).value == 3)
  }

  @Test
  func exactReadsRemainOpenUntilEndOfFileIsEncountered() async throws {
    let file = DataFile(data: Data("AB".utf8), mode: .read)
    let results = try await Interpreter.results(
      content: """
        /file (%cursor%input) (r) file def
        file 2 string readstring pop pop
        file status
        file bytesavailable
        file read
        file status
        file bytesavailable
        """,
      environment: environment(file: file)
    )

    #expect(try results[0].value(as: IntegerValue.self).value == -1)
    #expect(try !results[1].value(as: BooleanValue.self).value)
    #expect(try !results[2].value(as: BooleanValue.self).value)
    #expect(try results[3].value(as: IntegerValue.self).value == 0)
    #expect(try results[4].value(as: BooleanValue.self).value)
  }

  @Test
  func inputFlushReachesEndWithoutClosingAnOrdinaryFile() async throws {
    let file = DataFile(data: Data("AB".utf8), mode: .read)
    let results = try await Interpreter.results(
      content: """
        /file (%cursor%input) (r) file def
        file flushfile
        file status
        file read
        file status
        """,
      environment: environment(file: file)
    )

    #expect(try !results[0].value(as: BooleanValue.self).value)
    #expect(try !results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: BooleanValue.self).value)
  }

  @Test
  func inputSurfacesCloseOrdinaryFilesAfterEncounteringEndOfFile() async throws {
    let cases: [(Data, String)] = [
      (Data(), "file read pop"),
      (Data("A".utf8), "file 2 string readstring pop pop"),
      (Data("4".utf8), "file 2 string readhexstring pop pop"),
      (Data("A".utf8), "file 2 string readline pop pop"),
      (Data("name".utf8), "file token pop pop"),
    ]

    for (data, operation) in cases {
      let file = DataFile(data: data, mode: .read)
      let status: BooleanValue = try await Interpreter.result(
        content: """
          /file (%cursor%input) (r) file def
          \(operation)
          file status
          """,
        environment: environment(file: file)
      )
      #expect(!status.value)
    }
  }

  @Test
  func contextualTokenConsumesATerminatingCommentAsOneSeparator() async throws {
    for separator in ["%comment\n", "%comment\r", "%comment\r\n", "%comment\u{0C}"] {
      let source = "name\(separator)Z"
      let file = DataFile(data: Data(source.utf8), mode: .read)
      let results = try await Interpreter.results(
        content:
          """
          /file (%cursor%input) (r) file def
          file token pop pop
          file fileposition
          file read
          """,
        environment: environment(file: file)
      )

      #expect(try results[0].value(as: IntegerValue.self).value == 90)
      #expect(try results[1].value(as: BooleanValue.self).value)
      #expect(try results[2].value(as: IntegerValue.self).value == source.utf8.count - 1)
    }
  }

  @Test
  func executableFileClosesAfterItsFinalEndOfFileProbe() async throws {
    let file = DataFile(data: Data("1".utf8), mode: .read)
    let results = try await Interpreter.results(
      content: """
        /file (%cursor%input) (r) file def
        file cvx exec
        file status
        """,
      environment: environment(file: file)
    )

    #expect(try !results[0].value(as: BooleanValue.self).value)
    #expect(try results[1].value(as: IntegerValue.self).value == 1)
  }

  @Test
  func closedInputFilesReturnEndOfFileResults() async throws {
    let file = DataFile(data: Data("A".utf8), mode: .read)
    let results = try await Interpreter.results(
      content: """
        /file (%cursor%input) (r) file def
        file closefile
        file read
        file 2 string readstring
        file 2 string readhexstring
        file 2 string readline
        file token
        """,
      environment: environment(file: file)
    )

    #expect(results.count == 8)
    #expect(try !results[0].value(as: BooleanValue.self).value)
    for index in [1, 3, 5] {
      #expect(try !results[index].value(as: BooleanValue.self).value)
      #expect(try results[index + 1].value(as: StringValue.self).count == 0)
    }
    #expect(try !results[7].value(as: BooleanValue.self).value)
  }

  @Test
  func readLineRecognizesEveryEndOfLineFormAndPreservesLookahead() async throws {
    for data in ["A\nB", "A\rB", "A\r\nB"] {
      let file = DataFile(data: Data(data.utf8), mode: .read)
      let results = try await Interpreter.results(
        content: """
          /file (%cursor%input) (r) file def
          file 2 string readline
          file read
          """,
        environment: environment(file: file)
      )

      #expect(try results[0].value(as: IntegerValue.self).value == 66)
      #expect(try results[1].value(as: BooleanValue.self).value)
      #expect(try results[2].value(as: BooleanValue.self).value)
      #expect(try results[3].value(as: StringValue.self).string == "A")
    }
  }

  @Test
  func carriageReturnAtEndOfFileTerminatesTheLineAndClosesTheFile() async throws {
    let file = DataFile(data: Data("A\r".utf8), mode: .read)
    let results = try await Interpreter.results(
      content: """
        /file (%cursor%input) (r) file def
        file 2 string readline
        file status
        """,
      environment: environment(file: file)
    )

    #expect(try !results[0].value(as: BooleanValue.self).value)
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: StringValue.self).string == "A")
  }

  @Test
  func lineFeedAtEndOfFileDoesNotCloseUntilTheNextRead() async throws {
    let file = DataFile(data: Data("A\n".utf8), mode: .read)
    let results = try await Interpreter.results(
      content: """
        /file (%cursor%input) (r) file def
        file 2 string readline pop pop
        file status
        file read
        file status
        """,
      environment: environment(file: file)
    )

    #expect(try !results[0].value(as: BooleanValue.self).value)
    #expect(try !results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: BooleanValue.self).value)
  }

  @Test
  func readLineRangeCheckIsBoundedAndPreservesTheDestination() async throws {
    for (data, nextByte) in [("abc\nrest", 10), ("abcdef\n", 100)] {
      let file = DataFile(data: Data(data.utf8), mode: .read)
      let result: BooleanValue = try await Interpreter.result(
        content: """
          /file (%cursor%input) (r) file def
          /scratch 3 string def
          { file scratch readline } stopped pop clear
          $error /errorname get /rangecheck eq
          $error /command get /readline load eq and
          scratch 0 get 0 eq and
          file read exch pop \(nextByte) eq and
          """,
        environment: environment(file: file)
      )
      #expect(result.value)
    }

    let zeroLengthFile = DataFile(data: Data("A\n".utf8), mode: .read)
    let zeroLengthResult: BooleanValue = try await Interpreter.result(
      content: """
        /file (%cursor%input) (r) file def
        { file 0 string readline } stopped pop clear
        file read exch pop 65 eq
        """,
      environment: environment(file: zeroLengthFile)
    )
    #expect(zeroLengthResult.value)
  }

  @Test
  func cursorStateIsClearedByPositioningResetFlushAndClose() async throws {
    let positionFile = DataFile(data: Data("123<".utf8), mode: .read)
    let positionResult: IntegerValue = try await Interpreter.result(
      content: """
        /file (%cursor%input) (r) file def
        file token pop pop file 0 setfileposition file read exch pop
        """,
      environment: environment(file: positionFile)
    )
    #expect(positionResult.value == 49)

    for operation in ["resetfile", "flushfile"] {
      let file = DataFile(data: Data("123<".utf8), mode: .read)
      let result: BooleanValue = try await Interpreter.result(
        content: """
          /file (%cursor%input) (r) file def
          file token pop pop file \(operation) file read
          """,
        environment: environment(file: file)
      )
      #expect(!result.value)
    }

    let closeFile = DataFile(data: Data("123<".utf8), mode: .read)
    let closeResult: BooleanValue = try await Interpreter.result(
      content: """
        /file (%cursor%input) (r) file def
        file token pop pop file closefile file read
        """,
      environment: environment(file: closeFile)
    )
    #expect(!closeResult.value)
  }

  @Test
  func standardInputFeedsOrdinaryAndReusableFiltersContextually() async throws {
    let decoded: StringValue = try await Interpreter.result(
      content: "(%stdin) (r) file /ASCIIHexDecode filter 1 string readstring pop",
      environment: environment(standardInput: Data("41>".utf8))
    )
    #expect(decoded.string == "A")

    let reusable: StringValue = try await Interpreter.result(
      content: "(%stdin) (r) file /ReusableStreamDecode filter 2 string readstring pop",
      environment: environment(standardInput: Data("AB".utf8))
    )
    #expect(reusable.string == "AB")
  }

  @Test
  func inlineFilterEODReturnsControlToTheUnderlyingProgram() async throws {
    let input = Data(
      """
      currentfile /ASCIIHexDecode filter 2 string readstring
      41>
      pop 0 get /decoded exch def /continued true def
      """.utf8
    )
    let result: BooleanValue = try await Interpreter.result(
      content: "(%stdin) (r) file cvx exec decoded 65 eq continued and",
      environment: environment(standardInput: input)
    )
    #expect(result.value)
  }

  private func environment(standardInput: Data) -> InterpreterEnvironment {
    InterpreterEnvironment(
      hostConfiguration: InterpreterHostConfiguration(
        standardInput: DataSource(data: standardInput)
      )
    )
  }

  private func environment(file: any File) -> InterpreterEnvironment {
    InterpreterEnvironment(
      fileDevices: FileDevices(devices: [SharedFileDevice(file: file)])
    )
  }

}

private struct SharedFileDevice: FileDevice {
  let file: any File

  let searched = false
  let name = "cursor"

  func open(name: String, mode: File.Mode, openMethod: OpenMethod) throws -> any File {
    guard name == "input", mode == .read, openMethod == .existingOnly else {
      throw Error.undefinedFilename
    }
    return file
  }
}

private final class StreamingSource: Source, Sendable {
  private struct State: Sendable {
    var buffered = Data()
    var totalBytesRead = 0
    var finished = false
    var readStarted = false
    var readStartedWaiters: [CheckedContinuation<Void, Never>] = []
    var dataWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
  }

  private enum ReadState {
    case data(Data)
    case endOfFile
    case wait
  }

  private let state = Mutex(State())

  var bytesRead: Int { state.withLock(\.totalBytesRead) }

  func read(max: Int) async throws -> Data? {
    guard max >= 0 else { throw Error.rangeCheck }
    guard max > 0 else { return Data() }
    signalReadStarted()

    while true {
      switch take(max: max) {
      case .data(let data):
        return data
      case .endOfFile:
        return nil
      case .wait:
        try await waitForData()
      }
    }
  }

  func send(_ data: Data) {
    let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.buffered.append(data)
      let waiters = Array(state.dataWaiters.values)
      state.dataWaiters.removeAll()
      return waiters
    }
    for waiter in waiters { waiter.resume() }
  }

  func finish() {
    let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.finished = true
      let waiters = Array(state.dataWaiters.values)
      state.dataWaiters.removeAll()
      return waiters
    }
    for waiter in waiters { waiter.resume() }
  }

  func waitUntilReadStarted() async {
    let started = state.withLock(\.readStarted)
    guard !started else { return }
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state -> Bool in
        guard !state.readStarted else { return true }
        state.readStartedWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  func close() {
    finish()
  }

  private func signalReadStarted() {
    let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.readStarted = true
      let waiters = state.readStartedWaiters
      state.readStartedWaiters.removeAll()
      return waiters
    }
    for waiter in waiters { waiter.resume() }
  }

  private func take(max: Int) -> ReadState {
    state.withLock { state in
      if !state.buffered.isEmpty {
        let count = min(max, state.buffered.count)
        let result = Data(state.buffered.prefix(count))
        state.buffered.removeFirst(count)
        state.totalBytesRead += count
        return .data(result)
      }
      return state.finished ? .endOfFile : .wait
    }
  }

  private func waitForData() async throws {
    let identifier = UUID()
    try await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let resumeImmediately = state.withLock { state -> Bool in
          guard state.buffered.isEmpty, !state.finished, !Task.isCancelled else {
            return true
          }
          state.dataWaiters[identifier] = continuation
          return false
        }
        if resumeImmediately { continuation.resume() }
      }
      try Task<Never, Never>.checkCancellation()
    } onCancel: {
      let waiter = state.withLock { $0.dataWaiters.removeValue(forKey: identifier) }
      waiter?.resume()
    }
  }
}

private actor WaitingSink: Sink {
  private var storage = Data()
  private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  var bytesWritten: Int {
    get async throws { storage.count }
  }

  var data: Data { storage }

  func write(data: Data) {
    storage.append(data)
    let ready = waiters.filter { storage.count >= $0.count }
    waiters.removeAll { storage.count >= $0.count }
    for waiter in ready { waiter.continuation.resume() }
  }

  func waitForBytes(count: Int) async {
    guard storage.count < count else { return }
    await withCheckedContinuation { continuation in
      waiters.append((count, continuation))
    }
  }

  func close() {}
}
