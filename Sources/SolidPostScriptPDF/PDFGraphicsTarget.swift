import Foundation
import SolidPDF
import SolidPostScript

/// A vector-preserving PDF target writing to a typed output sink.
public struct PDFGraphicsTarget<Sink: PDFOutputSink>: GraphicsTarget, Sendable {
  public typealias PageOutput = PDFPageOutput
  public typealias Output = Sink.Session.Output
  public typealias FontEngine = PDFGraphicsFontEngine

  /// A renderer dedicated to one PDF document.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = PDFPageOutput
    public typealias Output = Sink.Session.Output
    public typealias FontSession = PDFGraphicsFontSession

    public private(set) var pages: [PDFPageOutput] = []

    private let sink: Sink
    private let options: PDFRenderOptions
    private let fontSession: PDFGraphicsFontSession
    private var descriptor: GraphicsDeviceDescriptor
    private var effects: [GraphicsEffect] = []
    private var plans: [PDFPagePlan] = []
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
    private var transmittedPageCount = 0
    private let storage = GraphicsStorageTracker()

    fileprivate init(
      sink: Sink,
      options: PDFRenderOptions,
      descriptor: GraphicsDeviceDescriptor,
      fontSession: PDFGraphicsFontSession
    ) {
      self.sink = sink
      self.options = options
      self.descriptor = descriptor
      self.fontSession = fontSession
    }

    public func process(_ event: GraphicsEvent) throws {
      guard !aborted, renderingEnabled else { return }
      switch event.operation {
      case .paint(.erasePage): try append(.erase(state: event.before))
      case .paint(.fill(let rule)):
        try append(.fill(path: event.before.path, rule: rule, state: event.before))
      case .paint(.stroke): try append(.stroke(path: event.before.path, state: event.before))
      case .paint(.userPathFill(let rule)):
        try append(.userPathFill(path: event.before.path, rule: rule, state: event.before))
      case .paint(.userPathStroke):
        try append(.userPathStroke(outline: event.before.path, state: event.before))
      case .paint(.fillRectangles(let paths)):
        try append(.fillRectangles(paths: paths, state: event.before))
      case .paint(.strokeRectangles(let paths, let matrix)):
        try append(.strokeRectangles(paths: paths, matrix: matrix, state: event.before))
      case .paint(.shading(let shading)):
        try append(.shading(shading, state: event.before))
      case .paint(.form(let form)):
        try append(.form(form, state: event.before))
      case .paint(.text(let run)):
        try append(.text(run, state: event.before))
      case .page(.show), .page(.copy):
        try transmitPage(event, copies: 1)
      default:
        break
      }
    }

    public func beginImage(_ event: GraphicsEvent) throws {
      guard !aborted, activeImage == nil, case .paint(.image(let descriptor)) = event.operation else {
        throw SolidPostScript.Error.ioError
      }
      try storage.beginImage()
      activeImage = (descriptor, event.before, [], [], [], 0)
    }

    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard var image = activeImage else { throw SolidPostScript.Error.ioError }
      try storage.resizeImage(to: try Self.imageBytes(
        components: image.components.count + rows.components.count,
        sourceComponents: image.sourceComponents.count + (rows.sourceComponents?.count ?? 0),
        mask: image.maskOpacities.count
      ))
      image.components.append(contentsOf: rows.components)
      if let source = rows.sourceComponents { image.sourceComponents.append(contentsOf: source) }
      activeImage = image
    }

    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
      guard var image = activeImage,
        let dimensions = Self.maskDimensions(for: image.descriptor),
        rows.startRow == image.nextMaskRow,
        rows.rowCount > 0,
        rows.rowCount <= dimensions.height - image.nextMaskRow,
        rows.opacities.count == rows.rowCount * dimensions.width
      else { throw SolidPostScript.Error.ioError }
      try storage.resizeImage(to: try Self.imageBytes(
        components: image.components.count,
        sourceComponents: image.sourceComponents.count,
        mask: image.maskOpacities.count + rows.opacities.count
      ))
      image.maskOpacities.append(contentsOf: rows.opacities)
      image.nextMaskRow += rows.rowCount
      activeImage = image
    }

    public func endImage() throws {
      guard let image = activeImage else { throw SolidPostScript.Error.ioError }
      activeImage = nil
      guard renderingEnabled, !image.components.isEmpty else {
        storage.abortImage()
        return
      }
      let effect = GraphicsEffect.image(
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
      try storage.endImage(effects: effects + [effect])
      effects.append(effect)
    }

    public func abortImage() {
      activeImage = nil
      storage.abortImage()
    }

    public func activateDevice(_ device: GraphicsDeviceSnapshot) {
      renderingEnabled = device.kind == .page
      if renderingEnabled { descriptor = device.descriptor }
    }

    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) {
      storage.clearCurrent()
      effects.removeAll(keepingCapacity: true)
    }

    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      guard !aborted, copies >= 0 else { throw SolidPostScript.Error.ioError }
      guard renderingEnabled else { return }
      let fallback = PDFPageAnalyzer.disposition(for: effects)
      if fallback != .vector, options.fallbackPolicy == .vectorOnly {
        throw SolidPostScript.Error.ioError
      }
      let selectedCopies = (0..<copies).reduce(into: 0) { count, _ in
        transmittedPageCount += 1
        if options.selectedPageOrdinals?.contains(transmittedPageCount) ?? true { count += 1 }
      }
      if selectedCopies > 0 {
        plans.append(PDFPagePlan(device: event.before.device, effects: effects, copies: selectedCopies))
        storage.transmit(retainingPage: true)
      } else {
        storage.transmit(retainingPage: false)
      }
      for _ in 0..<selectedCopies {
        pages.append(PDFPageOutput(
          ordinal: pages.count + 1,
          device: event.before.device,
          pageReference: PDFObjectReference(objectNumber: pages.count + 4),
          fallback: fallback
        ))
      }
      effects.removeAll(keepingCapacity: true)
    }

    public func finish() throws -> sending Sink.Session.Output {
      guard !aborted else { throw SolidPostScript.Error.ioError }
      if let requested = options.selectedPageOrdinals,
        requested.contains(where: { $0 > transmittedPageCount })
      {
        throw SolidPostScript.Error.rangeCheck
      }
      guard !plans.isEmpty else { throw SolidPostScript.Error.rangeCheck }
      aborted = true
      activeImage = nil
      do {
        let output = try PDFGraphicsDocumentEncoder.encode(plans: plans, sink: sink, options: options)
        storage.releaseAll()
        return output
      } catch {
        storage.releaseAll()
        throw SolidPostScript.Error.ioError
      }
    }

    public func abort() {
      aborted = true
      activeImage = nil
      effects.removeAll()
      plans.removeAll()
      pages.removeAll()
      storage.releaseAll()
    }

    public func installStorageAccounting(_ session: GraphicsStorageAccountingSession) {
      storage.install(session)
    }

    private func append(_ effect: GraphicsEffect) throws {
      try storage.updateCurrent(effects: effects + [effect])
      effects.append(effect)
    }

    private static func maskDimensions(
      for descriptor: GraphicsImageDescriptor
    ) -> (width: Int, height: Int)? {
      switch descriptor.mask {
      case .explicit(let width, let height, _, _): (width, height)
      case .colorKey: (descriptor.width, descriptor.height)
      case nil: nil
      }
    }

    private static func imageBytes(components: Int, sourceComponents: Int, mask: Int) throws -> Int {
      let values = components.addingReportingOverflow(sourceComponents)
      let all = values.partialValue.addingReportingOverflow(mask)
      let bytes = all.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      guard !values.overflow, !all.overflow, !bytes.overflow else {
        throw GraphicsStorageAccountingError.limitExceeded
      }
      return bytes.partialValue
    }
  }

  public let deviceDescriptor: GraphicsDeviceDescriptor
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider
  public let fontEngine = PDFGraphicsFontEngine()
  public let sink: Sink
  public let options: PDFRenderOptions

  /// Creates a PDF target.
  public init(
    sink: Sink,
    options: PDFRenderOptions = .init(),
    deviceDescriptor: GraphicsDeviceDescriptor = .letter
  ) {
    self.sink = sink
    self.options = options
    self.deviceDescriptor = deviceDescriptor
    pageDeviceProvider = StandardGraphicsPageDeviceProvider(
      mode: .adaptivePageSize,
      name: "SolidPDFPageDevice",
      colorantCapabilities: GraphicsColorantCapabilities(
        supportedProcessModels: Set(GraphicsProcessColorModel.allCases),
        supportsCompositeOutput: true,
        supportsSeparationOutput: false,
        supportsOverprint: true,
        acceptsDynamicColorants: true,
        maximumSeparations: 250
      )
    )
  }

  public func makeRenderer() -> sending Renderer {
    Renderer(
      sink: sink,
      options: options,
      descriptor: deviceDescriptor,
      fontSession: PDFGraphicsFontSession()
    )
  }

  public func makeRenderer(
    colorSession: sending SemanticGraphicsColorSession,
    deviceRenderingSession: sending SemanticGraphicsDeviceRenderingSession,
    fontSession: sending PDFGraphicsFontSession
  ) -> sending Renderer {
    Renderer(
      sink: sink,
      options: options,
      descriptor: deviceDescriptor,
      fontSession: fontSession
    )
  }

  public func makeRenderer(
    colorSession: sending SemanticGraphicsColorSession,
    deviceRenderingSession: sending SemanticGraphicsDeviceRenderingSession,
    fontSession: sending PDFGraphicsFontSession,
    trappingSession: sending SemanticGraphicsTrappingSession
  ) -> sending Renderer {
    Renderer(
      sink: sink,
      options: options,
      descriptor: deviceDescriptor,
      fontSession: fontSession
    )
  }
}

/// An in-memory vector PDF target.
public typealias PDFDataGraphicsTarget = PDFGraphicsTarget<PDFDataOutputSink>

/// An atomic-file vector PDF target.
public typealias PDFFileGraphicsTarget = PDFGraphicsTarget<PDFAtomicFileOutputSink>
