import Foundation
import SolidPDF
import SolidPostScript

/// A vector-preserving PDF target writing to a typed output sink.
public struct PDFGraphicsTarget<Sink: PDFOutputSink>: GraphicsTarget, Sendable {
  public typealias PageOutput = PDFPageOutput
  public typealias Output = Sink.Session.Output

  /// A renderer dedicated to one PDF document.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = PDFPageOutput
    public typealias Output = Sink.Session.Output

    public private(set) var pages: [PDFPageOutput] = []

    private let sink: Sink
    private let options: PDFRenderOptions
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

    fileprivate init(sink: Sink, options: PDFRenderOptions, descriptor: GraphicsDeviceDescriptor) {
      self.sink = sink
      self.options = options
      self.descriptor = descriptor
    }

    public func process(_ event: GraphicsEvent) throws {
      guard !aborted, renderingEnabled else { return }
      switch event.operation {
      case .paint(.erasePage): effects.append(.erase(state: event.before))
      case .paint(.fill(let rule)):
        effects.append(.fill(path: event.before.path, rule: rule, state: event.before))
      case .paint(.stroke): effects.append(.stroke(path: event.before.path, state: event.before))
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
      case .paint(.text(let run)):
        effects.append(.text(run, state: event.before))
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
      activeImage = (descriptor, event.before, [], [], [], 0)
    }

    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard var image = activeImage else { throw SolidPostScript.Error.ioError }
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
      image.maskOpacities.append(contentsOf: rows.opacities)
      image.nextMaskRow += rows.rowCount
      activeImage = image
    }

    public func endImage() throws {
      guard let image = activeImage else { throw SolidPostScript.Error.ioError }
      activeImage = nil
      guard renderingEnabled, !image.components.isEmpty else { return }
      effects.append(.image(
        GraphicsImage(
          descriptor: image.descriptor,
          components: image.components,
          sourceComponents: image.sourceComponents.isEmpty ? nil : image.sourceComponents,
          mask: image.descriptor.mask.map {
            GraphicsImageMask(descriptor: $0, opacities: image.maskOpacities)
          }
        ),
        state: image.state
      ))
    }

    public func abortImage() { activeImage = nil }

    public func activateDevice(_ device: GraphicsDeviceSnapshot) {
      renderingEnabled = device.kind == .page
      if renderingEnabled { descriptor = device.descriptor }
    }

    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) {
      effects.removeAll(keepingCapacity: true)
    }

    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      guard !aborted, copies >= 0 else { throw SolidPostScript.Error.ioError }
      guard renderingEnabled else { return }
      let fallback = PDFPageAnalyzer.disposition(for: effects)
      if fallback != .vector, options.fallbackPolicy == .vectorOnly {
        throw SolidPostScript.Error.ioError
      }
      plans.append(PDFPagePlan(device: event.before.device, effects: effects, copies: copies))
      for _ in 0..<copies {
        pages.append(PDFPageOutput(
          ordinal: pages.count + 1,
          device: event.before.device,
          fallback: fallback
        ))
      }
      effects.removeAll(keepingCapacity: true)
    }

    public func finish() throws -> sending Sink.Session.Output {
      guard !aborted else { throw SolidPostScript.Error.ioError }
      aborted = true
      activeImage = nil
      do {
        return try PDFGraphicsDocumentEncoder.encode(plans: plans, sink: sink, options: options)
      } catch {
        throw SolidPostScript.Error.ioError
      }
    }

    public func abort() {
      aborted = true
      activeImage = nil
      effects.removeAll()
      plans.removeAll()
      pages.removeAll()
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
  }

  public let deviceDescriptor: GraphicsDeviceDescriptor
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider
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
    Renderer(sink: sink, options: options, descriptor: deviceDescriptor)
  }
}

/// An in-memory vector PDF target.
public typealias PDFDataGraphicsTarget = PDFGraphicsTarget<PDFDataOutputSink>

/// An atomic-file vector PDF target.
public typealias PDFFileGraphicsTarget = PDFGraphicsTarget<PDFAtomicFileOutputSink>
