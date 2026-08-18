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
    private var activeImage: (descriptor: GraphicsImageDescriptor, state: GraphicsStateSnapshot, components: [Float])?
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
      case .paint(.userPathFill(let rule)):
        effects.append(.userPathFill(path: event.before.path, rule: rule, state: event.before))
      case .paint(.userPathStroke):
        effects.append(.userPathStroke(outline: event.before.path, state: event.before))
      case .paint(.fillRectangles(let paths)):
        effects.append(.fillRectangles(paths: paths, state: event.before))
      case .paint(.strokeRectangles(let paths, let matrix)):
        effects.append(.strokeRectangles(paths: paths, matrix: matrix, state: event.before))
      case .page(.show), .page(.copy):
        pages.append(RecordedGraphicsPage(deviceDescriptor: descriptor, effects: effects))
        effects.removeAll(keepingCapacity: true)
      default:
        break
      }
    }

    /// Begins recording one sampled image.
    public func beginImage(_ event: GraphicsEvent) throws {
      guard !aborted, activeImage == nil, case .paint(.image(let descriptor)) = event.operation else {
        throw Error.ioError
      }
      activeImage = (descriptor, event.before, [])
    }

    /// Records one bounded group of sampled-image rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard var image = activeImage else { throw Error.ioError }
      image.components.append(contentsOf: rows.components)
      activeImage = image
    }

    /// Commits the recorded sampled image.
    public func endImage() throws {
      guard let image = activeImage else { throw Error.ioError }
      if !image.components.isEmpty, image.descriptor.width > 0, image.descriptor.height > 0 {
        effects.append(
          .image(GraphicsImage(descriptor: image.descriptor, components: image.components), state: image.state)
        )
      }
      activeImage = nil
    }

    /// Abandons the active sampled image without recording it.
    public func abortImage() {
      activeImage = nil
    }

    /// Completes the recording and discards the untransmitted final page.
    public func finish() -> sending GraphicsRecording {
      GraphicsRecording(pages: pages)
    }

    /// Abandons all recorded output.
    public func abort() {
      aborted = true
      activeImage = nil
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
