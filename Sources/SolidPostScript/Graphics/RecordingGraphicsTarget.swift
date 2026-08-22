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
    /// Recordings retain hidden effects for later semantic analysis.
    public var preservesHiddenSemanticContent: Bool { true }

    private var descriptor: GraphicsDeviceDescriptor
    private var effects: [GraphicsEffect] = []
    private var renderingEnabled = true
    private var activeImage: (
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      components: [Float],
      sourceComponents: [Float],
      rawSamples: Data,
      maskOpacities: [Float],
      nextMaskRow: Int
    )?
    private var aborted = false
    private let storage = GraphicsStorageTracker()

    fileprivate init(descriptor: GraphicsDeviceDescriptor) {
      self.descriptor = descriptor
    }

    /// Processes one graphics event.
    public func process(_ event: GraphicsEvent) {
      guard !aborted, renderingEnabled else { return }
      switch event.operation {
      case .paint(.erasePage):
        append(.erase(state: event.before))
      case .paint(.fill(let rule)):
        append(.fill(path: event.before.path, rule: rule, state: event.before))
      case .paint(.stroke):
        append(.stroke(path: event.before.path, state: event.before))
      case .paint(.userPathFill(let rule)):
        append(.userPathFill(path: event.before.path, rule: rule, state: event.before))
      case .paint(.userPathStroke):
        append(.userPathStroke(outline: event.before.path, state: event.before))
      case .paint(.fillRectangles(let paths)):
        append(.fillRectangles(paths: paths, state: event.before))
      case .paint(.strokeRectangles(let paths, let matrix)):
        append(.strokeRectangles(paths: paths, matrix: matrix, state: event.before))
      case .paint(.shading(let shading)):
        append(.shading(shading, state: event.before))
      case .paint(.form(let form)):
        append(.form(form, state: event.before))
      case .paint(.text(let run)):
        append(.text(run, state: event.before))
      case .content(.markedContent(let operation)):
        append(.markedContent(operation, state: event.before))
      case .page(.show), .page(.copy):
        let transmission = GraphicsPageTransmission(
          trigger: event.operation == .page(.copy) ? .copyPage : .showPage,
          logicalOrdinal: pages.count + 1,
          copies: 1
        )
        pages.append(RecordedGraphicsPage(
          deviceDescriptor: event.before.device.descriptor,
          effects: effects,
          trapping: event.before.device.trapping,
          device: event.before.device,
          transmission: transmission
        ))
        storage.transmit(retainingPage: true)
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
      try storage.beginImage()
      activeImage = (descriptor, event.before, [], [], Data(), [], 0)
    }

    /// Records one bounded group of sampled-image rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard var image = activeImage else { throw Error.ioError }
      try storage.resizeImage(to: try imageBytes(
        components: image.components.count + rows.components.count,
        sourceComponents: image.sourceComponents.count + (rows.sourceComponents?.count ?? 0),
        mask: image.maskOpacities.count,
        rawBytes: image.rawSamples.count + (rows.rawSamples?.count ?? 0)
      ))
      image.components.append(contentsOf: rows.components)
      if let source = rows.sourceComponents {
        image.sourceComponents.append(contentsOf: source)
      }
      if let rawSamples = rows.rawSamples { image.rawSamples.append(rawSamples) }
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
      try storage.resizeImage(to: try imageBytes(
        components: image.components.count,
        sourceComponents: image.sourceComponents.count,
        mask: image.maskOpacities.count + rows.opacities.count,
        rawBytes: image.rawSamples.count
      ))
      image.maskOpacities.append(contentsOf: rows.opacities)
      image.nextMaskRow += rows.rowCount
      activeImage = image
    }

    /// Commits the recorded sampled image.
    public func endImage() throws {
      guard let image = activeImage else { throw Error.ioError }
      guard renderingEnabled else {
        storage.abortImage()
        activeImage = nil
        return
      }
      if !image.components.isEmpty, image.descriptor.width > 0, image.descriptor.height > 0 {
        let effect = GraphicsEffect.image(
          GraphicsImage(
            descriptor: image.descriptor,
            components: image.components,
            sourceComponents: image.sourceComponents.isEmpty ? nil : image.sourceComponents,
            rawSamples: image.rawSamples.isEmpty ? nil : image.rawSamples,
            mask: image.descriptor.mask.map {
              GraphicsImageMask(descriptor: $0, opacities: image.maskOpacities)
            }
          ),
          state: image.state
        )
        try storage.endImage(effects: effects + [effect])
        effects.append(effect)
      } else {
        storage.abortImage()
      }
      activeImage = nil
    }

    /// Abandons the active sampled image without recording it.
    public func abortImage() {
      storage.abortImage()
      activeImage = nil
    }

    /// Selects the descriptor associated with the active virtual device.
    public func activateDevice(_ device: GraphicsDeviceSnapshot) {
      renderingEnabled = device.kind == .page
      if renderingEnabled { descriptor = device.descriptor }
    }

    /// Discards the raster memory associated with a deactivated page device.
    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) {
      storage.clearCurrent()
      effects.removeAll(keepingCapacity: true)
    }

    /// Records the requested immutable copies and clears the transmitted page.
    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      try transmitPage(
        event,
        transmission: GraphicsPageTransmission(
          trigger: event.operation == .page(.copy) ? .copyPage : .showPage,
          logicalOrdinal: pages.count + 1,
          copies: copies
        )
      )
    }

    /// Records the requested immutable copies with complete transmission metadata.
    public func transmitPage(
      _ event: GraphicsEvent,
      transmission: GraphicsPageTransmission
    ) throws {
      guard transmission.copies >= 0 else { throw Error.ioError }
      if transmission.copies > 0 {
        for copyOrdinal in 1...transmission.copies {
          pages.append(RecordedGraphicsPage(
            deviceDescriptor: event.before.device.descriptor,
            effects: effects,
            trapping: event.before.device.trapping,
            device: event.before.device,
            transmission: transmission,
            copyOrdinal: copyOrdinal
          ))
        }
      }
      storage.transmit(retainingPage: true)
      effects.removeAll(keepingCapacity: true)
    }

    /// Completes the recording and discards the untransmitted final page.
    public func finish() -> sending GraphicsRecording {
      let output = GraphicsRecording(pages: pages)
      storage.releaseAll()
      return output
    }

    /// Abandons all recorded output.
    public func abort() {
      aborted = true
      activeImage = nil
      effects.removeAll()
      pages.removeAll()
      storage.releaseAll()
    }

    /// Installs Appendix C accounting for retained recording storage.
    public func installStorageAccounting(_ session: GraphicsStorageAccountingSession) {
      storage.install(session)
    }

    public func takeStorageAccountingError() -> GraphicsStorageAccountingError? {
      storage.takeError()
    }

    private func append(_ effect: GraphicsEffect) {
      if storage.updateCurrentDeferringError(effects: effects + [effect]) { effects.append(effect) }
    }

    private func imageBytes(
      components: Int,
      sourceComponents: Int,
      mask: Int,
      rawBytes: Int
    ) throws -> Int {
      let values = components.addingReportingOverflow(sourceComponents)
      let all = values.partialValue.addingReportingOverflow(mask)
      let bytes = all.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      let total = bytes.partialValue.addingReportingOverflow(rawBytes)
      guard !values.overflow, !all.overflow, !bytes.overflow, !total.overflow else {
        throw GraphicsStorageAccountingError.limitExceeded
      }
      return total.partialValue
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
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(
      mode: pageDeviceMode,
      colorantCapabilities: .semantic,
      trappingCapabilities: .semanticType1001
    )
  }

  /// Creates a renderer dedicated to one render operation.
  public func makeRenderer() -> sending Renderer {
    Renderer(descriptor: deviceDescriptor)
  }
}
