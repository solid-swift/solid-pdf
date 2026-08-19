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

  @Test func renderCreatesIndependentDeviceRenderingSession() async throws {
    let result = try await Interpreter.render(content: "", to: DeviceRenderingTarget())

    #expect(result.output == 37)
  }

  @Test func standardPageDeviceProviderNegotiatesAdaptiveGeometry() throws {
    let provider = StandardGraphicsPageDeviceProvider(mode: .adaptive)
    let session = try provider.makeSession(for: .letter)
    let result = try session.negotiate(GraphicsPageDeviceRequest(
      pageSize: GraphicsSize(width: 360, height: 720),
      resolution: GraphicsSize(width: 144, height: 144),
      imagingBoundingBox: GraphicsRect(x: 10, y: 20, width: 300, height: 600),
      numberOfCopies: 2
    ))

    #expect(result.unsatisfiedParameters.isEmpty)
    #expect(result.configuration.descriptor.mediaBounds.width == 720)
    #expect(result.configuration.descriptor.mediaBounds.height == 1_440)
    #expect(result.configuration.numberOfCopies == 2)
    #expect(result.configuration.identifier != session.initialConfiguration.identifier)
  }

  @Test func standardPageDeviceProviderReportsFixedGeometryChanges() throws {
    let provider = StandardGraphicsPageDeviceProvider(mode: .fixed)
    let session = try provider.makeSession(for: .letter)
    let result = try session.negotiate(GraphicsPageDeviceRequest(
      pageSize: GraphicsSize(width: 300, height: 400),
      resolution: GraphicsSize(width: 96, height: 96),
      imagingBoundingBox: nil,
      numberOfCopies: nil
    ))

    #expect(result.configuration.descriptor == .letter)
    #expect(result.unsatisfiedParameters == ["PageSize", "HWResolution"])
  }

  @Test func existingTargetsDefaultToFixedPageDeviceBehavior() throws {
    let target = ImageTransferTarget()
    let session = try target.pageDeviceProvider.makeSession(for: target.deviceDescriptor)

    #expect(session.capabilities.mode == .fixed)
    #expect(RecordingGraphicsTarget().pageDeviceProvider.mode == .adaptive)
    #expect(NullGraphicsTarget().pageDeviceProvider.mode == .adaptive)
  }

  @Test func sampledImageRowsAreTransferredInBoundedCompleteBatches() async throws {
    let row = String(repeating: "00", count: 64)
    let result = try await Interpreter.render(
      content: "64 40 8 [64 0 0 40 0 0] <\(row)> image",
      to: ImageTransferTarget()
    )

    #expect(result.output.totalRows == 40)
    #expect(result.output.maximumRowsPerTransfer <= 32)
    #expect(result.output.maximumComponentsPerTransfer <= 64 * 32)
  }
}

private struct DeviceRenderingTarget: GraphicsTarget {
  typealias PageOutput = Void
  typealias Output = Int
  typealias DeviceRenderingEngine = Engine

  struct Engine: GraphicsDeviceRenderingEngine {
    func makeSession(for device: GraphicsDeviceDescriptor) -> sending Session {
      Session(value: 37)
    }
  }

  final class Session: GraphicsDeviceRenderingSession {
    let value: Int

    init(value: Int) { self.value = value }

    func resolve(
      _ state: GraphicsDeviceRenderingSnapshot,
      for device: GraphicsDeviceDescriptor
    ) -> Int {
      value
    }
  }

  final class Renderer: GraphicsRenderer {
    typealias PageOutput = Void
    typealias Output = Int
    typealias DeviceRenderingSession = Session

    let session: Session
    var pages: [Void] = []

    init(session: Session) { self.session = session }

    func process(_ event: GraphicsEvent) {}
    func finish() -> sending Int { session.value }
    func abort() {}
  }

  let deviceDescriptor = GraphicsDeviceDescriptor.letter
  let deviceRenderingEngine = Engine()

  func makeRenderer() -> sending Renderer { Renderer(session: Session(value: -1)) }

  func makeRenderer(
    colorSession: sending SemanticGraphicsColorSession
  ) -> sending Renderer {
    Renderer(session: Session(value: -1))
  }

  func makeRenderer(
    colorSession: sending SemanticGraphicsColorSession,
    deviceRenderingSession: sending Session
  ) -> sending Renderer {
    Renderer(session: deviceRenderingSession)
  }
}

private struct ImageTransferTarget: GraphicsTarget {
  typealias PageOutput = Void
  typealias Output = Summary

  struct Summary: Sendable {
    let totalRows: Int
    let maximumRowsPerTransfer: Int
    let maximumComponentsPerTransfer: Int
  }

  final class Renderer: GraphicsRenderer {
    typealias PageOutput = Void
    typealias Output = Summary

    var pages: [Void] = []
    private var totalRows = 0
    private var maximumRows = 0
    private var maximumComponents = 0

    func process(_ event: GraphicsEvent) {}

    func beginImage(_ event: GraphicsEvent) {
      totalRows = 0
      maximumRows = 0
      maximumComponents = 0
    }

    func writeImageRows(_ rows: GraphicsImageRows) {
      totalRows += rows.rowCount
      maximumRows = max(maximumRows, rows.rowCount)
      maximumComponents = max(maximumComponents, rows.components.count)
    }

    func endImage() {}

    func finish() -> sending Summary {
      Summary(
        totalRows: totalRows,
        maximumRowsPerTransfer: maximumRows,
        maximumComponentsPerTransfer: maximumComponents
      )
    }

    func abort() {}
  }

  let deviceDescriptor = GraphicsDeviceDescriptor.letter

  func makeRenderer() -> sending Renderer { Renderer() }
}
