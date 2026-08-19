import Foundation
import SolidPostScript
import SolidRaster

/// A native raster target that produces ordered device-colorant plates and a diagnostic preview.
public struct RasterSeparationTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = RasterSeparatedPage
  public typealias Output = [RasterSeparatedPage]
  public typealias ColorEngine = NativeGraphicsColorEngine
  public typealias DeviceRenderingEngine = NativeGraphicsDeviceRenderingEngine
  public typealias PageDeviceProvider = StandardGraphicsPageDeviceProvider

  /// A renderer dedicated to one separated raster job.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RasterSeparatedPage
    public typealias Output = [RasterSeparatedPage]
    public typealias ColorSession = NativeGraphicsColorSession
    public typealias DeviceRenderingSession = NativeGraphicsDeviceRenderingSession

    public private(set) var pages: [RasterSeparatedPage] = []

    private let preview: RasterImageTarget.Renderer
    private var activeDevice: GraphicsDeviceSnapshot

    fileprivate init(
      preview: RasterImageTarget.Renderer,
      device: GraphicsDeviceSnapshot
    ) {
      self.preview = preview
      activeDevice = device
    }

    public func process(_ event: GraphicsEvent) throws { try preview.process(event) }
    public func beginImage(_ event: GraphicsEvent) throws { try preview.beginImage(event) }
    public func writeImageRows(_ rows: GraphicsImageRows) throws { try preview.writeImageRows(rows) }
    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws { try preview.writeImageMaskRows(rows) }
    public func endImage() throws { try preview.endImage() }
    public func abortImage() { preview.abortImage() }

    public func activateDevice(_ device: GraphicsDeviceSnapshot) throws {
      activeDevice = device
      try preview.activateDevice(device)
    }

    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws {
      preview.deactivateDevice(device)
    }

    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      let previousCount = preview.pages.count
      try preview.transmitPage(event, copies: copies)
      for image in preview.pages.dropFirst(previousCount) {
        pages.append(RasterSeparatedPage(device: activeDevice, plates: [], compositePreview: image))
      }
    }

    public func finish() throws -> sending [RasterSeparatedPage] {
      _ = try preview.finish()
      let result = pages
      pages.removeAll()
      return result
    }

    public func abort() {
      preview.abort()
      pages.removeAll()
    }
  }

  public let deviceDescriptor: GraphicsDeviceDescriptor
  public let colorEngine: NativeGraphicsColorEngine
  public let deviceRenderingEngine = NativeGraphicsDeviceRenderingEngine()
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider

  /// Creates a CMYK separation target.
  public init(
    deviceDescriptor: GraphicsDeviceDescriptor = .letter,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive
  ) {
    let colorants = GraphicsColorantConfiguration(
      processModel: .deviceCMYK,
      producesSeparations: true,
      separationOrder: ["Cyan", "Magenta", "Yellow", "Black"],
      maximumSeparations: 250,
      supportsOverprint: true
    )
    self.deviceDescriptor = GraphicsDeviceDescriptor(
      mediaBounds: deviceDescriptor.mediaBounds,
      imageableBounds: deviceDescriptor.imageableBounds,
      horizontalResolution: deviceDescriptor.horizontalResolution,
      verticalResolution: deviceDescriptor.verticalResolution,
      defaultMatrix: deviceDescriptor.defaultMatrix,
      defaultFlatness: deviceDescriptor.defaultFlatness,
      defaultStrokeAdjustment: deviceDescriptor.defaultStrokeAdjustment,
      minimumSmoothness: deviceDescriptor.minimumSmoothness,
      maximumSmoothness: deviceDescriptor.maximumSmoothness,
      defaultSmoothness: deviceDescriptor.defaultSmoothness,
      colorDevice: deviceDescriptor.colorDevice,
      deviceRendering: deviceDescriptor.deviceRendering,
      colorants: colorants
    )
    colorEngine = NativeGraphicsColorEngine()
    pageDeviceProvider = StandardGraphicsPageDeviceProvider(mode: pageDeviceMode)
  }

  public func makeRenderer() throws -> sending Renderer {
    let colorSession = try colorEngine.makeSession(for: deviceDescriptor)
    let renderingSession = deviceRenderingEngine.makeSession(for: deviceDescriptor)
    return try makeRenderer(colorSession: colorSession, deviceRenderingSession: renderingSession)
  }

  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession
  ) throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingEngine.makeSession(for: deviceDescriptor)
    )
  }

  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession,
    deviceRenderingSession: sending NativeGraphicsDeviceRenderingSession
  ) throws -> sending Renderer {
    let target = RasterImageTarget(
      pixelWidth: Int(deviceDescriptor.mediaBounds.width.rounded()),
      pixelHeight: Int(deviceDescriptor.mediaBounds.height.rounded()),
      deviceDescriptor: deviceDescriptor
    )
    let preview = try target.makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingSession
    )
    let snapshot = GraphicsDeviceSnapshot(
      identifier: GraphicsDeviceIdentifier(),
      kind: .page,
      descriptor: deviceDescriptor,
      pageNumber: 0,
      numberOfCopies: 1
    )
    return Renderer(preview: preview, device: snapshot)
  }
}
