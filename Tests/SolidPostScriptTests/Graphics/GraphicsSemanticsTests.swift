import Testing

@testable import SolidPostScript

@Suite
struct GraphicsSemanticsTests {

  @Test func graphicsStateOperatorsRestoreAndCopyState() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: """
      2 setlinewidth
      gsave 5 setlinewidth grestore currentlinewidth
      save 7 setlinewidth restore currentlinewidth
      gstate 9 setlinewidth currentgstate 4 setlinewidth setgstate currentlinewidth
      gstate 11 setlinewidth currentgstate gstate copy setgstate currentlinewidth
      """,
      count: 4
    )

    #expect(values.map(\.value) == [11, 9, 2, 2])
  }

  @Test func lineAndGrayStateValidation() async throws {
    let result = try await Interpreter.render(
      content: """
      4 setlinewidth 1 setlinecap 2 setlinejoin 12 setmiterlimit
      [3 2] 1 setdash .25 setgray
      currentgray currentdash currentmiterlimit currentlinejoin currentlinecap currentlinewidth
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()

    #expect(try values[0].value(as: RealValue.self).value == 4)
    #expect(try values[1].value(as: IntegerValue.self).value == 1)
    #expect(try values[2].value(as: IntegerValue.self).value == 2)
    #expect(try values[3].value(as: RealValue.self).value == 12)
    #expect(try values[4].value(as: RealValue.self).value == 1)
    #expect(try values[6].value(as: RealValue.self).value == 0.25)
  }

  @Test func matricesTransformPointsAndDistances() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: """
      10 20 translate 2 3 scale
      1 2 transform
      1 2 dtransform
      12 26 itransform
      2 6 idtransform
      """,
      count: 8
    )

    let expected: [Double] = [2, 1, 2, 1, 6, 2, 26, 12]
    for (actual, expected) in zip(values.map(\.value), expected) {
      #expect(abs(actual - expected) < 1e-12)
    }
  }

  @Test func pathsAreConstructedInDeviceSpaceAndClearedByPaint() async throws {
    let result = try await Interpreter.render(
      content: "2 3 scale 10 20 moveto 5 7 rlineto stroke showpage",
      to: RecordingGraphicsTarget()
    )
    let page = try #require(result.output.pages.first)
    guard case .stroke(let path, let state) = try #require(page.effects.first) else {
      Issue.record("Expected a stroke effect")
      return
    }

    #expect(path.elements == [
      .move(to: GraphicsPoint(x: 20, y: 60)),
      .line(to: GraphicsPoint(x: 30, y: 81)),
    ])
    #expect(state.matrix == GraphicsMatrix(a: 2, b: 0, c: 0, d: 3, tx: 0, ty: 0))
  }

  @Test func clippingAndPageTransmissionAreRecorded() async throws {
    let result = try await Interpreter.render(
      content: """
      newpath 0 0 moveto 100 0 lineto 100 100 lineto closepath clip
      .5 setgray newpath 10 10 moveto 20 10 lineto 20 20 lineto closepath fill
      showpage showpage
      newpath 0 0 moveto 1 1 lineto stroke
      """,
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.count == 2)
    #expect(result.output.pages[0].effects.count == 1)
    #expect(result.output.pages[1].effects.isEmpty)
    guard case .fill(_, .winding, let state) = try #require(result.output.pages[0].effects.first) else {
      Issue.record("Expected a fill effect")
      return
    }
    #expect(state.clip.constraints.count == 1)
  }

  @Test func errorsUseLanguageErrorLifecycle() async throws {
    let error: NameValue = try await Interpreter.result(
      content: "{0 0 lineto} stopped $error /errorname get"
    )
    #expect(error.value == "nocurrentpoint")
  }

  @Test func globalGraphicsStateRejectsLocalDashStorage() async {
    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "false setglobal [1] 0 setdash true setglobal gstate")
    }
  }

  @Test func rendererFailureBecomesIOError() async {
    await #expect(throws: Error.ioError) {
      try await Interpreter.render(
        content: "newpath 0 0 moveto 10 0 lineto stroke",
        to: FailingGraphicsTarget()
      )
    }
  }

  @Test func eventsPreserveOperationIntentAndStateTransition() async throws {
    let result = try await Interpreter.render(
      content: "2 setlinewidth 1 1 moveto 3 4 rlineto stroke showpage",
      to: EventGraphicsTarget()
    )

    #expect(result.output.map(\.operation) == [
      .state(.setLineWidth(2)),
      .path(.move(to: GraphicsPoint(x: 1, y: 1))),
      .path(.relativeLine(dx: 3, dy: 4)),
      .paint(.stroke),
      .page(.show),
    ])
    let stroke = result.output[3]
    #expect(stroke.before.path.currentPoint == GraphicsPoint(x: 4, y: 5))
    #expect(stroke.after.path.isEmpty)
  }
}

private struct EventGraphicsTarget: GraphicsTarget {
  typealias PageOutput = Void
  typealias Output = [GraphicsEvent]

  final class Renderer: GraphicsRenderer {
    typealias PageOutput = Void
    typealias Output = [GraphicsEvent]

    var pages: [Void] = []
    private var events: [GraphicsEvent] = []

    func process(_ event: GraphicsEvent) {
      events.append(event)
      if case .page(.show) = event.operation { pages.append(()) }
    }

    func finish() -> sending [GraphicsEvent] { events }
    func abort() { events.removeAll() }
  }

  let deviceDescriptor = GraphicsDeviceDescriptor.letter

  func makeRenderer() -> sending Renderer { Renderer() }
}

private struct FailingGraphicsTarget: GraphicsTarget {
  typealias PageOutput = Void
  typealias Output = Void

  final class Renderer: GraphicsRenderer {
    typealias PageOutput = Void
    typealias Output = Void

    var pages: [Void] { [] }

    func process(_ event: GraphicsEvent) throws {
      if case .paint = event.operation { throw Failure() }
    }

    func finish() -> sending Void {}
    func abort() {}
  }

  let deviceDescriptor = GraphicsDeviceDescriptor.letter

  func makeRenderer() -> sending Renderer { Renderer() }
}

private struct Failure: Swift.Error {}
