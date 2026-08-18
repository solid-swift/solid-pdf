import Foundation

/// Receives graphics events during one PostScript render and produces typed output.
public protocol GraphicsTarget<PageOutput, Output, Renderer>: Sendable {
  associatedtype PageOutput
  associatedtype Output
  associatedtype ColorEngine: GraphicsColorEngine = SemanticGraphicsColorEngine
  associatedtype Renderer: GraphicsRenderer<PageOutput, Output> where Renderer.ColorSession == ColorEngine.Session

  /// The device geometry and default transformation used for the render.
  var deviceDescriptor: GraphicsDeviceDescriptor { get }

  /// The color engine used to create render-scoped conversion state.
  var colorEngine: ColorEngine { get }

  /// Creates a renderer dedicated to one render operation.
  func makeRenderer() throws -> sending Renderer

  /// Creates a renderer using color state prepared by the interpreter.
  func makeRenderer(colorSession: sending ColorEngine.Session) throws -> sending Renderer
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

/// Consumes validated graphics events without defining an output type.
public protocol GraphicsEventConsumer: AnyObject {
  /// Processes one successful graphics operation.
  func process(_ event: GraphicsEvent) throws
  /// Begins one sampled-image transfer described by an image paint event.
  func beginImage(_ event: GraphicsEvent) throws
  /// Consumes a bounded group of complete sampled-image rows.
  func writeImageRows(_ rows: GraphicsImageRows) throws
  /// Commits the active sampled-image transfer.
  func endImage() throws
  /// Abandons the active sampled-image transfer after a language or renderer error.
  func abortImage()
  /// Abandons the current render without producing output.
  func abort()
}

extension GraphicsEventConsumer {
  /// Processes the image operation for consumers that do not retain sample rows.
  public func beginImage(_ event: GraphicsEvent) throws { try process(event) }
  /// Ignores image rows for consumers that do not render sampled images.
  public func writeImageRows(_ rows: GraphicsImageRows) throws {}
  /// Completes a no-op image transfer.
  public func endImage() throws {}
  /// Completes a no-op image abandonment.
  public func abortImage() {}
}

/// Consumes graphics events and completes a typed sequence of pages and job output.
public protocol GraphicsRenderer<PageOutput, Output>: GraphicsEventConsumer {
  associatedtype PageOutput
  associatedtype Output
  associatedtype ColorSession: GraphicsColorSession = SemanticGraphicsColorSession

  /// Pages transmitted so far.
  var pages: [PageOutput] { get }
  /// Completes the render, discarding an untransmitted final page.
  func finish() throws -> sending Output
}
