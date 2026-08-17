import Testing

@testable import SolidPostScript

@Suite
struct GraphicsTargetTests {

  @Test func matrixCompositionAndInversion() throws {
    let translate = GraphicsMatrix(a: 1, b: 0, c: 0, d: 1, tx: 10, ty: 20)
    let scale = GraphicsMatrix(a: 2, b: 0, c: 0, d: 3, tx: 0, ty: 0)
    let composed = translate.concatenated(with: scale)

    #expect(composed.transform(GraphicsPoint(x: 1, y: 2)) == GraphicsPoint(x: 22, y: 66))
    let inverse = try #require(composed.inverted)
    #expect(inverse.transform(composed.transform(GraphicsPoint(x: 4, y: 5))) == GraphicsPoint(x: 4, y: 5))
    #expect(GraphicsMatrix(a: 1, b: 0, c: 0, d: 0, tx: 0, ty: 0).inverted == nil)
  }

  @Test func recordingRendererKeepsOnlyRealizedPages() throws {
    let target = RecordingGraphicsTarget()
    let renderer = target.makeRenderer()
    let state = GraphicsStateSnapshot(
      matrix: .identity,
      path: GraphicsPath(elements: [.move(to: GraphicsPoint(x: 0, y: 0))]),
      clip: GraphicsClip(imageableBounds: target.deviceDescriptor.imageableBounds),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )

    renderer.process(GraphicsEvent(operation: .state(.setGray(0)), before: state, after: state))
    renderer.process(GraphicsEvent(operation: .paint(.fill(.winding)), before: state, after: state))
    renderer.process(GraphicsEvent(operation: .page(.show), before: state, after: state))
    renderer.process(GraphicsEvent(operation: .paint(.stroke), before: state, after: state))

    let output = renderer.finish()
    #expect(output.pages.count == 1)
    #expect(output.pages[0].effects.count == 1)
  }

  @Test func renderUsesPerCallRendererWithSharedEnvironment() async throws {
    let environment = InterpreterEnvironment()

    async let first = Interpreter.render(
      content: "1 2 add",
      to: RecordingGraphicsTarget(),
      environment: environment
    )
    async let second = Interpreter.render(
      content: "3 4 add",
      to: RecordingGraphicsTarget(),
      environment: environment
    )

    let (firstResult, secondResult) = try await (first, second)
    #expect(firstResult.output.pages.isEmpty)
    #expect(secondResult.output.pages.isEmpty)
    #expect(try await firstResult.context.results().first?.value(as: IntegerValue.self).value == 3)
    #expect(try await secondResult.context.results().first?.value(as: IntegerValue.self).value == 7)
  }

  @Test func genericOpeningPreservesRendererFamily() throws {
    func open<Target: GraphicsTarget>(_ target: Target) throws -> Target.Renderer {
      try target.makeRenderer()
    }

    let renderer = try open(RecordingGraphicsTarget())
    let output = renderer.finish()
    #expect(output.pages.isEmpty)
  }
}
