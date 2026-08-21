import Testing
@testable import SolidPostScript

@Suite
struct GraphicsStorageAccountingTests {

  @Test
  func reservationsTrackCategoriesAndReleaseExactlyOnce() throws {
    let ledger = GraphicsStorageLedger()
    let session = ledger.makeSession()
    let display = try session.reserve(.displayList, bytes: 128)
    let source = try session.reserve(.sourceList, bytes: 64)
    let image = try session.reserve(.imageBuffer, bytes: 32)

    var status = ledger.status()
    #expect(status.displayBytes == 128)
    #expect(status.sourceBytes == 96)

    try display.resize(to: 256)
    try image.resize(to: 48)
    status = ledger.status()
    #expect(status.displayBytes == 256)
    #expect(status.sourceBytes == 112)

    display.release()
    display.release()
    source.release()
    image.release()
    status = ledger.status()
    #expect(status.displayBytes == 0)
    #expect(status.sourceBytes == 0)
  }

  @Test
  func recordingPublishesLiveDisplayAndSourceUsage() async throws {
    let environment = InterpreterEnvironment()
    let result = try await Interpreter.render(
      content:
        """
        newpath 0 0 moveto 10 0 lineto 10 10 lineto closepath fill
        currentsystemparams /CurDisplayList get
        1 1 8 [1 0 0 -1 0 1] <80> image
        currentsystemparams /CurSourceList get
        showpage
        currentsystemparams /CurDisplayList get
        """,
      to: RecordingGraphicsTarget(),
      environment: environment
    )
    let values = try await result.context.results().map { try $0.value(as: IntegerValue.self).value }
    #expect(values.count == 3)
    #expect(values.allSatisfy { $0 > 0 })

    let status = environment.graphicsStorageLedger.status()
    #expect(status.displayBytes == 0)
    #expect(status.sourceBytes == 0)
  }

  @Test
  func concurrentSessionsAggregateWithoutLeaking() async throws {
    let ledger = GraphicsStorageLedger()
    let session = ledger.makeSession()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<32 {
        group.addTask {
          let reservation = try session.reserve(.displayList, bytes: 1_024)
          #expect(reservation.bytes == 1_024)
          reservation.release()
        }
      }
      try await group.waitForAll()
    }
    #expect(ledger.status().displayBytes == 0)
  }
}
