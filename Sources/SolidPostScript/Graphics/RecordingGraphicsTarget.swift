import Foundation

/// A portable graphics target that records realized page effects.
public struct RecordingGraphicsTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = RecordedGraphicsPage
  public typealias Output = GraphicsRecording

  /// The per-render recording renderer.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RecordedGraphicsPage
    public typealias Output = GraphicsRecording

    /// Pages transmitted so far.
    public private(set) var pages: [RecordedGraphicsPage] = []

    private let descriptor: GraphicsDeviceDescriptor
    private var effects: [GraphicsEffect] = []
    private var aborted = false

    fileprivate init(descriptor: GraphicsDeviceDescriptor) {
      self.descriptor = descriptor
    }

    /// Processes one graphics event.
    public func process(_ event: GraphicsEvent) {
      guard !aborted else { return }
      switch event.operation {
      case .paint(.erasePage):
        effects.append(.erase(state: event.before))
      case .paint(.fill(let rule)):
        effects.append(.fill(path: event.before.path, rule: rule, state: event.before))
      case .paint(.stroke):
        effects.append(.stroke(path: event.before.path, state: event.before))
      case .page(.show):
        pages.append(RecordedGraphicsPage(deviceDescriptor: descriptor, effects: effects))
        effects.removeAll(keepingCapacity: true)
      default:
        break
      }
    }

    /// Completes the recording and discards the untransmitted final page.
    public func finish() -> sending GraphicsRecording {
      GraphicsRecording(pages: pages)
    }

    /// Abandons all recorded output.
    public func abort() {
      aborted = true
      effects.removeAll()
      pages.removeAll()
    }
  }

  /// The device descriptor used by this target.
  public let deviceDescriptor: GraphicsDeviceDescriptor

  /// Creates a recording target.
  public init(deviceDescriptor: GraphicsDeviceDescriptor = .letter) {
    self.deviceDescriptor = deviceDescriptor
  }

  /// Creates a renderer dedicated to one render operation.
  public func makeRenderer() -> sending Renderer {
    Renderer(descriptor: deviceDescriptor)
  }
}
