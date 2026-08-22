/// A bounded target that forwards the canonical PostScript semantic stream to a caller-owned sink.
public struct SemanticGraphicsTarget<Sink: GraphicsSemanticSink>: GraphicsTarget, Sendable {
  public typealias PageOutput = Never
  public typealias Output = Sink.Session.Output

  /// The render-scoped forwarding renderer.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = Never
    public typealias Output = Sink.Session.Output

    /// Semantic targets do not retain materialized pages.
    public var pages: [Never] { [] }

    private let session: Sink.Session
    private var imageActive = false
    private var finished = false
    private var abandoned = false

    fileprivate init(session: sending Sink.Session) {
      self.session = session
    }

    /// Forwards one graphics event.
    public func process(_ event: GraphicsEvent) throws {
      try forward { try session.receive(event) }
    }

    /// Begins one transactional image after forwarding its semantic event.
    public func beginImage(_ event: GraphicsEvent) throws {
      guard !imageActive else { throw Error.ioError }
      do {
        try session.receive(event)
        try session.beginImage(event)
        imageActive = true
      } catch {
        throw Error.ioError
      }
    }

    /// Forwards ordered image color rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard imageActive else { throw Error.ioError }
      try forward { try session.writeImageRows(rows) }
    }

    /// Forwards ordered image mask rows.
    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
      guard imageActive else { throw Error.ioError }
      try forward { try session.writeImageMaskRows(rows) }
    }

    /// Completes the active image exactly once.
    public func endImage() throws {
      guard imageActive else { throw Error.ioError }
      do {
        try session.endImage()
        imageActive = false
      } catch {
        imageActive = false
        session.abandonImage()
        throw Error.ioError
      }
    }

    /// Abandons the active image exactly once.
    public func abortImage() {
      guard imageActive else { return }
      imageActive = false
      session.abandonImage()
    }

    /// Forwards device activation.
    public func activateDevice(_ device: GraphicsDeviceSnapshot) throws {
      try forward { try session.activateDevice(device) }
    }

    /// Forwards device deactivation.
    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws {
      try forward { try session.deactivateDevice(device) }
    }

    /// Adapts an ordinary transmission to complete metadata.
    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      try transmitPage(event, transmission: GraphicsPageTransmission(
        trigger: event.operation == .page(.copy) ? .copyPage : .showPage,
        logicalOrdinal: 1,
        copies: copies
      ))
    }

    /// Forwards the page event and complete transmission metadata without duplicating effects.
    public func transmitPage(
      _ event: GraphicsEvent,
      transmission: GraphicsPageTransmission
    ) throws {
      do {
        try session.receive(event)
        try session.transmitPage(event, transmission: transmission)
      } catch {
        throw Error.ioError
      }
    }

    /// Completes the sink and returns its output.
    public func finish() throws -> sending Output {
      guard !finished, !abandoned, !imageActive else { throw Error.ioError }
      do {
        let output = try session.finish()
        finished = true
        return output
      } catch {
        throw Error.ioError
      }
    }

    /// Abandons the active transaction and render.
    public func abort() {
      guard !finished, !abandoned else { return }
      abortImage()
      abandoned = true
      session.abandon()
    }

    private func forward(_ body: () throws -> Void) throws {
      guard !finished, !abandoned else { throw Error.ioError }
      do { try body() } catch { throw Error.ioError }
    }
  }

  /// The device geometry and default transformation used for the render.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The virtual page-device provider used by this target.
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider
  /// The sink used to create render-scoped sessions.
  public let sink: Sink

  /// Creates a streaming semantic target.
  public init(
    sink: Sink,
    deviceDescriptor: GraphicsDeviceDescriptor = .letter,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive
  ) {
    self.sink = sink
    self.deviceDescriptor = deviceDescriptor
    pageDeviceProvider = StandardGraphicsPageDeviceProvider(
      mode: pageDeviceMode,
      colorantCapabilities: .semantic,
      trappingCapabilities: .semanticType1001
    )
  }

  /// Creates a renderer dedicated to one semantic stream.
  public func makeRenderer() throws -> sending Renderer {
    try Renderer(session: sink.makeSession(contractVersion: .current))
  }
}
