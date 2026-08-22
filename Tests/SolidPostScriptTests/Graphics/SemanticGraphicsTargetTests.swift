import Testing

@testable import SolidPostScript

@Suite struct SemanticGraphicsTargetTests {
  @Test func targetStreamsEventsLifecycleAndTransmissionWithoutMaterializingPages() async throws {
    let result = try await Interpreter.render(
      content: "0 0 10 10 rectfill showpage",
      to: SemanticGraphicsTarget(sink: TestSink())
    )

    #expect(result.output.contractVersion == .v4)
    #expect(result.output.activated.count == 1)
    #expect(result.output.deactivated.count == 1)
    #expect(result.output.events.count == 2)
    #expect(result.output.transmissions.count == 1)
    #expect(result.output.transmissions[0].copies == 1)
    #expect(result.output.finished)
    #expect(!result.output.abandoned)
  }

  @Test func sinkFailureBecomesPostScriptIOError() async throws {
    do {
      _ = try await Interpreter.render(
        content: "0 0 10 10 rectfill showpage",
        to: SemanticGraphicsTarget(sink: FailingSink())
      )
      Issue.record("Expected the sink failure to abort rendering")
    } catch let error as Error {
      #expect(error == .ioError)
    }
  }

  @Test func streamingAndRecordingTargetsReceiveEquivalentPaintSemantics() async throws {
    let program = "0.25 setgray 2 3 11 13 rectfill showpage"
    let semantic = try await Interpreter.render(
      content: program,
      to: SemanticGraphicsTarget(sink: TestSink())
    )
    let recording = try await Interpreter.render(content: program, to: RecordingGraphicsTarget())
    let collector = GraphicsEffectCollector()

    for event in semantic.output.events {
      if case .page = event.operation { continue }
      collector.process(event)
    }

    guard case .fillRectangles(let streamedPaths, let streamedState) = collector.effects.first,
      case .fillRectangles(let recordedPaths, let recordedState) = recording.output.pages.first?.effects.first
    else {
      Issue.record("Expected corresponding rectangle effects")
      return
    }
    #expect(streamedPaths == recordedPaths)
    #expect(streamedState.paint == recordedState.paint)
    #expect(streamedState.colorSpace == recordedState.colorSpace)
    #expect(streamedState.matrix == recordedState.matrix)
    #expect(streamedState.clip == recordedState.clip)
  }
}

private struct TestSink: GraphicsSemanticSink {
  func makeSession(contractVersion: GraphicsSemanticContractVersion) -> sending TestSession {
    TestSession(contractVersion: contractVersion)
  }
}

private final class TestSession: GraphicsSemanticSinkSession {
  struct Result: Sendable {
    let contractVersion: GraphicsSemanticContractVersion
    let activated: [GraphicsDeviceSnapshot]
    let deactivated: [GraphicsDeviceSnapshot]
    let events: [GraphicsEvent]
    let transmissions: [GraphicsPageTransmission]
    let finished: Bool
    let abandoned: Bool
  }

  private let contractVersion: GraphicsSemanticContractVersion
  private var activated: [GraphicsDeviceSnapshot] = []
  private var deactivated: [GraphicsDeviceSnapshot] = []
  private var events: [GraphicsEvent] = []
  private var transmissions: [GraphicsPageTransmission] = []
  private var imageActive = false
  private var abandoned = false

  init(contractVersion: GraphicsSemanticContractVersion) {
    self.contractVersion = contractVersion
  }

  func activateDevice(_ device: GraphicsDeviceSnapshot) { activated.append(device) }
  func deactivateDevice(_ device: GraphicsDeviceSnapshot) { deactivated.append(device) }
  func receive(_ event: GraphicsEvent) { events.append(event) }
  func beginImage(_ event: GraphicsEvent) throws {
    guard !imageActive else { throw TestFailure() }
    imageActive = true
  }
  func writeImageRows(_ rows: GraphicsImageRows) throws {
    guard imageActive else { throw TestFailure() }
  }
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
    guard imageActive else { throw TestFailure() }
  }
  func endImage() throws {
    guard imageActive else { throw TestFailure() }
    imageActive = false
  }
  func abandonImage() { imageActive = false }
  func transmitPage(_ event: GraphicsEvent, transmission: GraphicsPageTransmission) {
    transmissions.append(transmission)
  }
  func finish() -> sending Result {
    Result(
      contractVersion: contractVersion,
      activated: activated,
      deactivated: deactivated,
      events: events,
      transmissions: transmissions,
      finished: true,
      abandoned: abandoned
    )
  }
  func abandon() { abandoned = true }
}

private struct FailingSink: GraphicsSemanticSink {
  func makeSession(contractVersion: GraphicsSemanticContractVersion) -> sending FailingSession {
    FailingSession()
  }
}

private final class FailingSession: GraphicsSemanticSinkSession {
  func activateDevice(_ device: GraphicsDeviceSnapshot) {}
  func deactivateDevice(_ device: GraphicsDeviceSnapshot) {}
  func receive(_ event: GraphicsEvent) throws { throw TestFailure() }
  func beginImage(_ event: GraphicsEvent) {}
  func writeImageRows(_ rows: GraphicsImageRows) {}
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) {}
  func endImage() {}
  func abandonImage() {}
  func transmitPage(_ event: GraphicsEvent, transmission: GraphicsPageTransmission) {}
  func finish() -> sending Void {}
  func abandon() {}
}

private struct TestFailure: Swift.Error {}
