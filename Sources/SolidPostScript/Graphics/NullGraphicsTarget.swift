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

    /// Records the requested number of discarded page transmissions.
    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      guard copies >= 0 else { throw Error.ioError }
      pages.append(contentsOf: repeatElement((), count: copies))
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
  /// The virtual page-device provider used by this target.
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider

  /// Creates a null target.
  public init(
    deviceDescriptor: GraphicsDeviceDescriptor = .letter,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive
  ) {
    self.deviceDescriptor = deviceDescriptor
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(
      mode: pageDeviceMode,
      colorantCapabilities: .semantic
    )
  }

  /// Creates a renderer dedicated to one execution.
  public func makeRenderer() -> sending Renderer {
    Renderer()
  }
}
