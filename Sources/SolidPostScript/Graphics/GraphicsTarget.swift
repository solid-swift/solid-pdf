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
  /// Abandons the current render without producing output.
  func abort()
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
