import Foundation

/// Receives graphics events during one PostScript render and produces typed output.
public protocol GraphicsTarget<PageOutput, Output, Renderer>: Sendable {
  associatedtype PageOutput
  associatedtype Output
  associatedtype ColorEngine: GraphicsColorEngine = SemanticGraphicsColorEngine
  associatedtype DeviceRenderingEngine: GraphicsDeviceRenderingEngine = SemanticGraphicsDeviceRenderingEngine
  associatedtype FontEngine: GraphicsFontEngine = SemanticGraphicsFontEngine
  associatedtype TrappingEngine: GraphicsTrappingEngine = SemanticGraphicsTrappingEngine
  associatedtype PageDeviceProvider: GraphicsPageDeviceProvider = StandardGraphicsPageDeviceProvider
  associatedtype Renderer: GraphicsRenderer<PageOutput, Output>
    where Renderer.ColorSession == ColorEngine.Session,
      Renderer.DeviceRenderingSession == DeviceRenderingEngine.Session,
      Renderer.FontSession == FontEngine.Session,
      Renderer.TrappingSession == TrappingEngine.Session

  /// The device geometry and default transformation used for the render.
  var deviceDescriptor: GraphicsDeviceDescriptor { get }

  /// The color engine used to create render-scoped conversion state.
  var colorEngine: ColorEngine { get }

  /// The device-rendering engine used to create render-scoped transfer and halftone state.
  var deviceRenderingEngine: DeviceRenderingEngine { get }

  /// The font engine used to create render-scoped glyph preparation state.
  var fontEngine: FontEngine { get }

  /// The trapping engine used to prepare render-scoped trapping programs.
  var trappingEngine: TrappingEngine { get }

  /// The provider used to negotiate page geometry during this render.
  var pageDeviceProvider: PageDeviceProvider { get }

  /// Creates a renderer dedicated to one render operation.
  func makeRenderer() throws -> sending Renderer

  /// Creates a renderer using color state prepared by the interpreter.
  func makeRenderer(colorSession: sending ColorEngine.Session) throws -> sending Renderer

  /// Creates a renderer using color and device-rendering state prepared by the interpreter.
  func makeRenderer(
    colorSession: sending ColorEngine.Session,
    deviceRenderingSession: sending DeviceRenderingEngine.Session
  ) throws -> sending Renderer

  /// Creates a renderer using color, device-rendering, and font state prepared by the interpreter.
  func makeRenderer(
    colorSession: sending ColorEngine.Session,
    deviceRenderingSession: sending DeviceRenderingEngine.Session,
    fontSession: sending FontEngine.Session
  ) throws -> sending Renderer

  /// Creates a renderer using all render-scoped device services.
  func makeRenderer(
    colorSession: sending ColorEngine.Session,
    deviceRenderingSession: sending DeviceRenderingEngine.Session,
    fontSession: sending FontEngine.Session,
    trappingSession: sending TrappingEngine.Session
  ) throws -> sending Renderer
}

extension GraphicsTarget where PageDeviceProvider == StandardGraphicsPageDeviceProvider {
  /// A fixed provider preserving source compatibility for targets that do not select one.
  public var pageDeviceProvider: StandardGraphicsPageDeviceProvider {
    StandardGraphicsPageDeviceProvider(mode: .fixed)
  }
}

extension GraphicsTarget where ColorEngine == SemanticGraphicsColorEngine {
  /// The source-compatible semantic color engine used by targets that do not select one.
  public var colorEngine: SemanticGraphicsColorEngine { SemanticGraphicsColorEngine() }

  /// Creates the existing renderer while preserving source compatibility for custom targets.
  public func makeRenderer(
    colorSession: sending SemanticGraphicsColorSession
  ) throws -> sending Renderer {
    try makeRenderer()
  }
}

extension GraphicsTarget where DeviceRenderingEngine == SemanticGraphicsDeviceRenderingEngine {
  /// The source-compatible semantic rendering engine used by targets that do not select one.
  public var deviceRenderingEngine: SemanticGraphicsDeviceRenderingEngine {
    SemanticGraphicsDeviceRenderingEngine()
  }

  /// Creates the existing renderer while preserving source compatibility for custom targets.
  public func makeRenderer(
    colorSession: sending ColorEngine.Session,
    deviceRenderingSession: sending SemanticGraphicsDeviceRenderingSession
  ) throws -> sending Renderer {
    try makeRenderer(colorSession: colorSession)
  }
}

extension GraphicsTarget where FontEngine == SemanticGraphicsFontEngine {
  /// The source-compatible semantic font engine used by targets that do not select one.
  public var fontEngine: SemanticGraphicsFontEngine { SemanticGraphicsFontEngine() }

  /// Creates the existing renderer while preserving source compatibility for custom targets.
  public func makeRenderer(
    colorSession: sending ColorEngine.Session,
    deviceRenderingSession: sending DeviceRenderingEngine.Session,
    fontSession: sending SemanticGraphicsFontSession
  ) throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingSession
    )
  }
}

extension GraphicsTarget where TrappingEngine == SemanticGraphicsTrappingEngine {
  /// The source-compatible semantic trapping engine used by targets that do not select one.
  public var trappingEngine: SemanticGraphicsTrappingEngine { SemanticGraphicsTrappingEngine() }

  /// Creates the existing renderer while preserving source compatibility for custom targets.
  public func makeRenderer(
    colorSession: sending ColorEngine.Session,
    deviceRenderingSession: sending DeviceRenderingEngine.Session,
    fontSession: sending FontEngine.Session,
    trappingSession: sending SemanticGraphicsTrappingSession
  ) throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingSession,
      fontSession: fontSession
    )
  }
}

/// Consumes validated graphics events without defining an output type.
public protocol GraphicsEventConsumer: AnyObject {
  /// Processes one successful graphics operation.
  func process(_ event: GraphicsEvent) throws
  /// Begins one sampled-image transfer described by an image paint event.
  func beginImage(_ event: GraphicsEvent) throws
  /// Consumes a bounded group of complete sampled-image rows.
  func writeImageRows(_ rows: GraphicsImageRows) throws
  /// Consumes a bounded group of complete sampled-image mask rows.
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws
  /// Commits the active sampled-image transfer.
  func endImage() throws
  /// Abandons the active sampled-image transfer after a language or renderer error.
  func abortImage()
  /// Activates a page or null device for subsequent graphics events.
  func activateDevice(_ device: GraphicsDeviceSnapshot) throws
  /// Deactivates a page device and discards its retained page raster.
  func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws
  /// Transmits the current page one or more times before clearing its raster.
  func transmitPage(_ event: GraphicsEvent, copies: Int) throws
  /// Transmits the current page with complete physical delivery metadata.
  func transmitPage(_ event: GraphicsEvent, transmission: GraphicsPageTransmission) throws
  /// Abandons the current render without producing output.
  func abort()
  /// Removes a deferred accounting failure from a source-compatible nonthrowing consumer.
  func takeStorageAccountingError() -> GraphicsStorageAccountingError?
}

extension GraphicsEventConsumer {
  /// Processes the image operation for consumers that do not retain sample rows.
  public func beginImage(_ event: GraphicsEvent) throws { try process(event) }
  /// Ignores image rows for consumers that do not render sampled images.
  public func writeImageRows(_ rows: GraphicsImageRows) throws {}
  /// Rejects nonempty mask data unless a consumer implements mask realization.
  public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
    guard rows.rowCount == 0, rows.opacities.isEmpty else { throw Error.ioError }
  }
  /// Completes a no-op image transfer.
  public func endImage() throws {}
  /// Completes a no-op image abandonment.
  public func abortImage() {}
  /// Accepts device activation when the target does not retain device-specific state.
  public func activateDevice(_ device: GraphicsDeviceSnapshot) throws {}
  /// Accepts device deactivation when the target does not retain device-specific state.
  public func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws {}
  /// Preserves existing single-copy behavior and rejects unsupported multiple copies.
  public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
    guard copies == 1 else { throw Error.ioError }
    try process(event)
  }
  /// Adapts virtual uncollated transmissions to the original page-consumer contract.
  public func transmitPage(_ event: GraphicsEvent, transmission: GraphicsPageTransmission) throws {
    guard !transmission.delivery.requiresPhysicalDelivery,
      transmission.mediaSelection == .virtual,
      transmission.placement == .simplex
    else { throw Error.ioError }
    try transmitPage(event, copies: transmission.copies)
  }
  /// Reports no deferred accounting failure by default.
  public func takeStorageAccountingError() -> GraphicsStorageAccountingError? { nil }
}

/// Consumes graphics events and completes a typed sequence of pages and job output.
public protocol GraphicsRenderer<PageOutput, Output>: GraphicsEventConsumer {
  associatedtype PageOutput
  associatedtype Output
  associatedtype ColorSession: GraphicsColorSession = SemanticGraphicsColorSession
  associatedtype DeviceRenderingSession: GraphicsDeviceRenderingSession = SemanticGraphicsDeviceRenderingSession
  associatedtype FontSession: GraphicsFontSession = SemanticGraphicsFontSession
  associatedtype TrappingSession: GraphicsTrappingSession = SemanticGraphicsTrappingSession

  /// Pages transmitted so far.
  var pages: [PageOutput] { get }
  /// Whether the renderer retains hidden semantic paint for document analysis.
  var preservesHiddenSemanticContent: Bool { get }
  /// Installs render-scoped Appendix C storage accounting before device activation.
  func installStorageAccounting(_ session: GraphicsStorageAccountingSession) throws
  /// Completes the render, discarding an untransmitted final page.
  func finish() throws -> sending Output
}

extension GraphicsRenderer {
  /// Visual renderers omit painting operations whose evaluated visibility is hidden.
  public var preservesHiddenSemanticContent: Bool { false }
  /// Leaves renderer-owned storage outside Appendix C accounting for source compatibility.
  public func installStorageAccounting(_ session: GraphicsStorageAccountingSession) throws {}
}
