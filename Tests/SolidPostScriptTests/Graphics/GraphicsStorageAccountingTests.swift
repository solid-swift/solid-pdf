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

  @Test
  func individualCombinedAndImageLimitsAreExact() throws {
    let ledger = GraphicsStorageLedger()
    ledger.setLimits(display: 128, source: 64, combined: 160, imageBuffer: 32)
    let session = ledger.makeSession()
    let display = try session.reserve(.displayList, bytes: 128)
    let source = try session.reserve(.sourceList, bytes: 32)

    #expect(throws: GraphicsStorageAccountingError.limitExceeded) {
      try source.resize(to: 33)
    }
    source.release()
    let image = try session.reserve(.imageBuffer, bytes: 32)
    #expect(throws: GraphicsStorageAccountingError.limitExceeded) {
      try image.resize(to: 33)
    }

    display.release()
    image.release()
  }

  @Test
  func loweringLiveLimitBlocksGrowthUntilUsageFalls() throws {
    let ledger = GraphicsStorageLedger()
    let reservation = try ledger.makeSession().reserve(.displayList, bytes: 128)
    ledger.setLimits(display: 64, source: 64, combined: 64, imageBuffer: 64)

    #expect(throws: GraphicsStorageAccountingError.limitExceeded) {
      try reservation.resize(to: 129)
    }
    try reservation.resize(to: 64)
    #expect(throws: GraphicsStorageAccountingError.limitExceeded) {
      try reservation.resize(to: 65)
    }
  }

  @Test
  func graphicsLimitFailureIsAttributedToTriggeringOperator() async throws {
    let result = try await Interpreter.render(
      content:
        """
        << /MaxDisplayList 255 >> setsystemparams
        { newpath 0 0 moveto 10 0 lineto 10 10 lineto closepath fill } stopped
        $error /errorname get /limitcheck eq
        $error /command get /fill load eq
        """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()
    let booleans = values.compactMap { try? $0.value(as: BooleanValue.self).value }
    #expect(booleans.count == 3)
    #expect(booleans.allSatisfy { $0 })
  }

  @Test
  func imageLimitFailureIsTransactionalAndAttributedToImage() async throws {
    let result = try await Interpreter.render(
      content:
        """
        << /MaxImageBuffer 3 >> setsystemparams
        { 1 1 8 [1 0 0 -1 0 1] <80> image } stopped
        $error /errorname get /limitcheck eq
        $error /command get /image load eq
        currentsystemparams /CurSourceList get 0 eq
        """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()
    let booleans = values.compactMap { try? $0.value(as: BooleanValue.self).value }
    #expect(booleans.count == 4)
    #expect(booleans.allSatisfy { $0 })
  }
}
