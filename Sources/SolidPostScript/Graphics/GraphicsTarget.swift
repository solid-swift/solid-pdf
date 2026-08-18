import Foundation

/// Receives graphics events during one PostScript render and produces typed output.
public protocol GraphicsTarget<PageOutput, Output, Renderer>: Sendable {
  associatedtype PageOutput
  associatedtype Output
  associatedtype Renderer: GraphicsRenderer<PageOutput, Output>

  /// The device geometry and default transformation used for the render.
  var deviceDescriptor: GraphicsDeviceDescriptor { get }

  /// Creates a renderer dedicated to one render operation.
  func makeRenderer() throws -> sending Renderer
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

  /// Pages transmitted so far.
  var pages: [PageOutput] { get }
  /// Completes the render, discarding an untransmitted final page.
  func finish() throws -> sending Output
}
