import Foundation

/// A graphics target that validates semantics and discards all visible output.
public struct NullGraphicsTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = Void
  public typealias Output = Void

  /// The per-render renderer used by the null target.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = Void
    public typealias Output = Void

    /// The transmitted pages, represented only by their count.
    public private(set) var pages: [Void] = []

    /// Creates a null renderer.
    public init() {}

    /// Processes one graphics event.
    public func process(_ event: GraphicsEvent) {
      if case .page = event.operation {
        pages.append(())
      }
    }

    /// Completes the render.
    public func finish() -> sending Void {}

    /// Abandons the render.
    public func abort() {
      pages.removeAll()
    }
  }

  /// The default Letter-sized 72-dpi graphics device.
  public let deviceDescriptor: GraphicsDeviceDescriptor

  /// Creates a null target.
  public init(deviceDescriptor: GraphicsDeviceDescriptor = .letter) {
    self.deviceDescriptor = deviceDescriptor
  }

  /// Creates a renderer dedicated to one execution.
  public func makeRenderer() -> sending Renderer {
    Renderer()
  }
}
