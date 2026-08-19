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

    private var descriptor: GraphicsDeviceDescriptor
    private var effects: [GraphicsEffect] = []
    private var renderingEnabled = true
    private var activeImage: (
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      components: [Float],
      sourceComponents: [Float],
      maskOpacities: [Float],
      nextMaskRow: Int
    )?
    private var aborted = false

    fileprivate init(descriptor: GraphicsDeviceDescriptor) {
      self.descriptor = descriptor
    }

    /// Processes one graphics event.
    public func process(_ event: GraphicsEvent) {
      guard !aborted, renderingEnabled else { return }
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
      case .paint(.shading(let shading)):
        effects.append(.shading(shading, state: event.before))
      case .paint(.form(let form)):
        effects.append(.form(form, state: event.before))
      case .page(.show), .page(.copy):
        pages.append(RecordedGraphicsPage(deviceDescriptor: event.before.device.descriptor, effects: effects))
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
      activeImage = (descriptor, event.before, [], [], [], 0)
    }

    /// Records one bounded group of sampled-image rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard var image = activeImage else { throw Error.ioError }
      image.components.append(contentsOf: rows.components)
      if let source = rows.sourceComponents {
        image.sourceComponents.append(contentsOf: source)
      }
      activeImage = image
    }

    /// Records one bounded group of explicit mask rows.
    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
      guard var image = activeImage,
        let dimensions = maskDimensions(for: image.descriptor),
        dimensions.width > 0,
        dimensions.height > 0,
        rows.rowCount > 0,
        rows.startRow == image.nextMaskRow,
        rows.rowCount <= dimensions.height - image.nextMaskRow,
        rows.rowCount <= Int.max / dimensions.width,
        rows.opacities.count == rows.rowCount * dimensions.width
      else { throw Error.ioError }
      image.maskOpacities.append(contentsOf: rows.opacities)
      image.nextMaskRow += rows.rowCount
      activeImage = image
    }

    /// Commits the recorded sampled image.
    public func endImage() throws {
      guard let image = activeImage else { throw Error.ioError }
      guard renderingEnabled else {
        activeImage = nil
        return
      }
      if !image.components.isEmpty, image.descriptor.width > 0, image.descriptor.height > 0 {
        effects.append(
          .image(
            GraphicsImage(
              descriptor: image.descriptor,
              components: image.components,
              sourceComponents: image.sourceComponents.isEmpty ? nil : image.sourceComponents,
              mask: image.descriptor.mask.map {
                GraphicsImageMask(descriptor: $0, opacities: image.maskOpacities)
              }
            ),
            state: image.state
          )
        )
      }
      activeImage = nil
    }

    /// Abandons the active sampled image without recording it.
    public func abortImage() {
      activeImage = nil
    }

    /// Selects the descriptor associated with the active virtual device.
    public func activateDevice(_ device: GraphicsDeviceSnapshot) {
      renderingEnabled = device.kind == .page
      if renderingEnabled { descriptor = device.descriptor }
    }

    /// Discards the raster memory associated with a deactivated page device.
    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) {
      effects.removeAll(keepingCapacity: true)
    }

    /// Records the requested immutable copies and clears the transmitted page.
    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      guard copies >= 0 else { throw Error.ioError }
      let page = RecordedGraphicsPage(deviceDescriptor: event.before.device.descriptor, effects: effects)
      pages.append(contentsOf: repeatElement(page, count: copies))
      effects.removeAll(keepingCapacity: true)
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

    private func maskDimensions(for descriptor: GraphicsImageDescriptor) -> (width: Int, height: Int)? {
      switch descriptor.mask {
      case .explicit(let width, let height, _, _): (width, height)
      case .colorKey: (descriptor.width, descriptor.height)
      case nil: nil
      }
    }
  }

  /// The device descriptor used by this target.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The virtual page-device provider used by this target.
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider

  /// Creates a recording target.
  public init(
    deviceDescriptor: GraphicsDeviceDescriptor = .letter,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive
  ) {
    self.deviceDescriptor = deviceDescriptor
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(mode: pageDeviceMode)
  }

  /// Creates a renderer dedicated to one render operation.
  public func makeRenderer() -> sending Renderer {
    Renderer(descriptor: deviceDescriptor)
  }
}
