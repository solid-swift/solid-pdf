import SolidPostScript
import SolidRaster

/// A native raster target that sends each transmitted page to a bounded sink.
public struct RasterPageSinkTarget<Sink: RasterPageSink>: GraphicsTarget, Sendable {
  public typealias PageOutput = RasterRenderedPage
  public typealias Output = Sink.Session.Output
  public typealias ColorEngine = NativeGraphicsColorEngine
  public typealias DeviceRenderingEngine = NativeGraphicsDeviceRenderingEngine

  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RasterRenderedPage
    public typealias Output = Sink.Session.Output
    public typealias ColorSession = NativeGraphicsColorSession
    public typealias DeviceRenderingSession = NativeGraphicsDeviceRenderingSession

    public var pages: [RasterRenderedPage] { [] }

    private let core: RasterImageTarget.Renderer
    private let sink: Sink.Session
    private var transmissionOrdinal = 0
    private var activeDevice: GraphicsDeviceSnapshot?

    fileprivate init(core: RasterImageTarget.Renderer, sink: sending Sink.Session) {
      self.core = core
      self.sink = sink
    }

    public func process(_ event: GraphicsEvent) throws { try core.process(event) }
    public func beginImage(_ event: GraphicsEvent) throws { try core.beginImage(event) }
    public func writeImageRows(_ rows: GraphicsImageRows) throws { try core.writeImageRows(rows) }
    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws { try core.writeImageMaskRows(rows) }
    public func endImage() throws { try core.endImage() }
    public func abortImage() { core.abortImage() }

    public func activateDevice(_ device: GraphicsDeviceSnapshot) throws {
      activeDevice = device
      try core.activateDevice(device)
    }

    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws {
      core.deactivateDevice(device)
      if activeDevice?.identifier == device.identifier { activeDevice = nil }
    }

    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      try core.transmitPage(event, copies: copies)
      let transmitted = core.drainTransmittedPages()
      guard transmitted.count == copies else { throw SolidPostScript.Error.ioError }
      let device = activeDevice ?? event.before.device
      transmissionOrdinal += 1
      for (copy, image) in transmitted.enumerated() {
        try sink.consume(.init(
          image: image,
          device: device,
          transmissionOrdinal: transmissionOrdinal,
          copyOrdinal: copy + 1
        ))
      }
    }

    public func finish() throws -> sending Sink.Session.Output {
      let remainder = try core.finish()
      guard remainder.isEmpty else { throw SolidPostScript.Error.ioError }
      return try sink.finish()
    }

    public func abort() {
      core.abort()
      sink.abort()
    }
  }

  public let deviceDescriptor: GraphicsDeviceDescriptor
  public let colorEngine: NativeGraphicsColorEngine
  public let deviceRenderingEngine = NativeGraphicsDeviceRenderingEngine()
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider
  public let sink: Sink
  private let pixelWidth: Int
  private let pixelHeight: Int
  private let background: RasterColor

  /// Creates a streaming target with explicit pixel geometry.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    resolution: Double = 72,
    background: RasterColor = .white,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive,
    sink: Sink
  ) {
    let media = GraphicsRect(x: 0, y: 0, width: Double(pixelWidth), height: Double(pixelHeight))
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.deviceDescriptor = GraphicsDeviceDescriptor(
      mediaBounds: media,
      imageableBounds: media,
      horizontalResolution: resolution,
      verticalResolution: resolution,
      defaultMatrix: .init(a: resolution / 72, b: 0, c: 0, d: resolution / 72, tx: 0, ty: 0)
    )
    self.colorEngine = NativeGraphicsColorEngine()
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(mode: pageDeviceMode)
    self.sink = sink
    self.background = background
  }

  /// Creates a streaming target using an explicit PostScript device descriptor.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    deviceDescriptor: GraphicsDeviceDescriptor,
    background: RasterColor = .white,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive,
    sink: Sink
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.deviceDescriptor = deviceDescriptor
    self.colorEngine = NativeGraphicsColorEngine(
      destinationProfile: deviceDescriptor.colorDevice.destinationProfile
    )
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(mode: pageDeviceMode)
    self.sink = sink
    self.background = background
  }

  public func makeRenderer() throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorEngine.makeSession(for: deviceDescriptor),
      deviceRenderingSession: deviceRenderingEngine.makeSession(for: deviceDescriptor)
    )
  }

  public func makeRenderer(colorSession: sending NativeGraphicsColorSession) throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingEngine.makeSession(for: deviceDescriptor)
    )
  }

  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession,
    deviceRenderingSession: sending NativeGraphicsDeviceRenderingSession
  ) throws -> sending Renderer {
    let target = RasterImageTarget(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      deviceDescriptor: deviceDescriptor,
      background: background,
      pageDeviceMode: pageDeviceProvider.mode
    )
    return try Renderer(
      core: target.makeRenderer(
        colorSession: colorSession,
        deviceRenderingSession: deviceRenderingSession
      ),
      sink: sink.makeSession()
    )
  }
}
