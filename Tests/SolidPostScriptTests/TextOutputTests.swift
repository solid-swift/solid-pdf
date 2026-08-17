import Foundation
import SolidIO
import Synchronization
@testable import SolidPostScript
import Testing

@Suite
struct TextOutputTests {

  @Test
  func operatorsAreRegisteredWithProcedureTypes() async throws {
    let values: [NameValue] = try await Interpreter.result(
      content: "/= load type /== load type /print load type /stack load type /pstack load type",
      count: 5
    )
    #expect(values.map(\.value) == ["operatortype", "operatortype", "operatortype", "arraytype", "arraytype"])
  }

  @Test
  func printWritesRawBytesWithoutANewline() async throws {
    let sink = DataSink()
    _ = try await Interpreter.execute(
      content: "<0041ff> print",
      environment: InterpreterEnvironment(standardOutput: sink)
    )
    #expect(sink.data == Data([0x00, 0x41, 0xFF]))
  }

  @Test
  func equalsUsesValueFormattingAndConsumesItsOperand() async throws {
    let sink = DataSink()
    let results = try await Interpreter.results(
      content: "42 = 1.5 = true = /literal = (bytes) = 1 dict = count",
      environment: InterpreterEnvironment(standardOutput: sink)
    )
    #expect(String(data: sink.data, encoding: .isoLatin1) == "42\n1.5\ntrue\nliteral\nbytes\n--nostringval--\n")
    #expect(try results[0].value(as: IntegerValue.self).value == 0)
  }

  @Test
  func doubleEqualsUsesPostScriptSyntaxAndProtectsInaccessibleValues() async throws {
    let sink = DataSink()
    _ = try await Interpreter.execute(
      content: "/literal == {name} 0 get == <28295c0a00> == [1 /x (s)] == {1 /x (s)} == 1 dict == (secret) noaccess ==",
      environment: InterpreterEnvironment(standardOutput: sink)
    )
    #expect(
      String(data: sink.data, encoding: .isoLatin1)
        == "/literal\nname\n(\\(\\)\\\\\\n\\000)\n[1 /x (s)]\n{1 /x (s)}\n-dict-\n-string-\n"
    )
  }

  @Test
  func doubleEqualsDoesNotTreatADisjointSharedIntervalAsRecursive() async throws {
    let sink = DataSink()
    _ = try await Interpreter.execute(
      content: "/array [null 1] def array 0 array 1 1 getinterval put array ==",
      environment: InterpreterEnvironment(standardOutput: sink)
    )

    #expect(String(data: sink.data, encoding: .isoLatin1) == "[[1] 1]\n")
  }

  @Test
  func stackAndPStackPrintTopmostFirstWithoutMutation() async throws {
    let valueSink = DataSink()
    let valueResults = try await Interpreter.results(
      content: "1 /two (three) stack count",
      environment: InterpreterEnvironment(standardOutput: valueSink)
    )
    #expect(String(data: valueSink.data, encoding: .isoLatin1) == "three\ntwo\n1\n")
    #expect(try valueResults[0].value(as: IntegerValue.self).value == 3)

    let syntaxSink = DataSink()
    let syntaxResults = try await Interpreter.results(
      content: "1 /two (three) pstack count",
      environment: InterpreterEnvironment(standardOutput: syntaxSink)
    )
    #expect(String(data: syntaxSink.data, encoding: .isoLatin1) == "(three)\n/two\n1\n")
    #expect(try syntaxResults[0].value(as: IntegerValue.self).value == 3)
  }

  @Test
  func explicitStdoutAndImplicitOutputShareTheConfiguredSink() async throws {
    let sink = RecordingSink()
    _ = try await Interpreter.execute(
      content: "(a) print (%stdout) (w) file dup (b) writestring dup flushfile closefile (c) print flush",
      environment: InterpreterEnvironment(standardOutput: sink)
    )
    #expect(sink.data == Data("abc".utf8))
    #expect(sink.flushCount == 3)
    #expect(!sink.closed)
  }

  @Test
  func closingStdoutDoesNotCloseTheBorrowedSinkAndKeepsJobIdentity() async throws {
    let sink = RecordingSink()
    let results = try await Interpreter.results(
      content:
        "(%stdout) (w) file dup (a) writestring closefile (b) print {(%stdout) (w) file (c) writestring} stopped",
      environment: InterpreterEnvironment(standardOutput: sink)
    )
    #expect(sink.data == Data("ab".utf8))
    #expect(sink.flushCount == 1)
    #expect(!sink.closed)
    #expect(try results[0].value(as: BooleanValue.self).value)
  }

  @Test
  func closingNoAccessStdoutStillFlushes() async throws {
    let sink = RecordingSink()
    _ = try await Interpreter.execute(
      content: "(%stdout) (w) file noaccess closefile",
      environment: InterpreterEnvironment(standardOutput: sink)
    )

    #expect(sink.flushCount == 1)
    #expect(!sink.closed)
  }

  @Test
  func failedCloseFlushLeavesTheLogicalFileOpen() async throws {
    let sink = FailingFlushSink()
    let results = try await Interpreter.results(
      content:
        """
        /standard (%stdout) (w) file def
        standard (a) writestring
        { standard closefile } stopped pop clear
        standard status
        $error /errorname get
        """,
      environment: InterpreterEnvironment(standardOutput: sink)
    )

    #expect(sink.data == Data("a".utf8))
    #expect(sink.flushCount == 1)
    #expect(results.count == 2)
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
    #expect(results.contains { ($0.value as? NameValue)?.value == "ioerror" })
  }

  @Test
  func filtersTargetingStdoutUseTheConfiguredSink() async throws {
    let sink = DataSink()
    _ = try await Interpreter.execute(
      content: "(%stdout) (w) file /ASCIIHexEncode filter dup (Hi) writestring closefile",
      environment: InterpreterEnvironment(standardOutput: sink)
    )
    #expect(sink.data == Data("4869\n>".utf8))
  }

  @Test
  func outputFailuresEnterErrorDictAndStopped() async throws {
    let results = try await Interpreter.results(
      content: "{(x) print} stopped $error /errorname get",
      environment: InterpreterEnvironment(standardOutput: FailingSink())
    )
    #expect(try results[0].value(as: NameValue.self).value == "ioerror")
    #expect(try results[1].value(as: BooleanValue.self).value)
  }

  @Test
  func sharedEnvironmentSerializesSuspendingSinkWrites() async throws {
    let sink = SuspendingSink()
    let environment = InterpreterEnvironment(standardOutput: sink)
    let a = String(repeating: "(A) print ", count: 50)
    let b = String(repeating: "(B) print ", count: 50)

    async let first = Interpreter.execute(content: a, environment: environment)
    async let second = Interpreter.execute(content: b, environment: environment)
    _ = try await (first, second)

    #expect(sink.data.count == 100)
    #expect(sink.data.filter { $0 == Character("A").asciiValue }.count == 50)
    #expect(sink.data.filter { $0 == Character("B").asciiValue }.count == 50)
    #expect(sink.maximumConcurrentWrites == 1)
  }

  @Test
  func recursiveArraysUseAnOpaqueCycleMarker() throws {
    let array = try ArrayValue(elements: [.null], access: .unlimited, vm: .local)
    let object = Object(value: array, kind: .literal)
    try array.updateObject(object, at: 0)
    var formatter = PostScriptTextFormatter(mode: .syntax)
    #expect(String(data: formatter.format(object), encoding: .isoLatin1) == "[-array-]")
  }
}

private final class RecordingSink: Sink, Flushable, Sendable {
  private struct State: Sendable {
    var data = Data()
    var flushCount = 0
    var closed = false
  }

  private let state = Mutex(State())

  var data: Data { state.withLock(\.data) }
  var flushCount: Int { state.withLock(\.flushCount) }
  var closed: Bool { state.withLock(\.closed) }
  var bytesWritten: Int { state.withLock { $0.data.count } }

  func write(data: Data) {
    state.withLock { $0.data.append(data) }
  }

  func flush() {
    state.withLock { $0.flushCount += 1 }
  }

  func close() {
    state.withLock { $0.closed = true }
  }
}

private struct FailingSink: Sink {
  var bytesWritten: Int { 0 }

  func write(data: Data) throws {
    throw Failure.write
  }

  func close() {}

  private enum Failure: Swift.Error {
    case write
  }
}

private final class FailingFlushSink: Sink, Flushable, Sendable {
  private struct State: Sendable {
    var data = Data()
    var flushCount = 0
  }

  private let state = Mutex(State())

  var data: Data { state.withLock(\.data) }
  var flushCount: Int { state.withLock(\.flushCount) }
  var bytesWritten: Int { state.withLock { $0.data.count } }

  func write(data: Data) {
    state.withLock { $0.data.append(data) }
  }

  func flush() throws {
    state.withLock { $0.flushCount += 1 }
    throw Failure.flush
  }

  func close() {}

  private enum Failure: Swift.Error {
    case flush
  }
}

private final class SuspendingSink: Sink, Sendable {
  private struct State: Sendable {
    var data = Data()
    var activeWrites = 0
    var maximumConcurrentWrites = 0
  }

  private let state = Mutex(State())

  var data: Data { state.withLock(\.data) }
  var bytesWritten: Int { state.withLock { $0.data.count } }
  var maximumConcurrentWrites: Int { state.withLock(\.maximumConcurrentWrites) }

  func write(data: Data) async {
    state.withLock { state in
      state.activeWrites += 1
      state.maximumConcurrentWrites = max(state.maximumConcurrentWrites, state.activeWrites)
    }
    await Task.yield()
    state.withLock { state in
      state.data.append(data)
      state.activeWrites -= 1
    }
  }

  func close() {}
}
