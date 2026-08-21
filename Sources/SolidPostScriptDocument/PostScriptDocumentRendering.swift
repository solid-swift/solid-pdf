import Foundation
import SolidPostScript
import SolidPostScriptRaster
import SolidRaster

extension PostScriptDocument {
  /// Renders the complete document to an arbitrary graphics target.
  public func render<Target: GraphicsTarget>(
    to target: Target,
    environment: InterpreterEnvironment = .init()
  ) async throws -> GraphicsRenderResult<Target.Output> {
    if metadata.kind == .encapsulatedPostScript, let bounds = metadata.bounds {
      return try await Interpreter.renderEncapsulated(
        file: usesStagedStandardInput ? nil : DataFile(data: programData, mode: .read),
        bounds: bounds.graphics,
        strict: true,
        to: target,
        environment: environment
      )
    }
    if usesStagedStandardInput {
      return try await Interpreter.renderStandardInput(to: target, environment: environment)
    }
    return try await Interpreter.render(
      file: DataFile(data: programData, mode: .read),
      to: target,
      environment: environment
    )
  }

  /// Renders selected transmitted pages through the native Swift raster target.
  public func renderRaster(
    options: PostScriptDocumentRenderOptions = .init(),
    environment: InterpreterEnvironment = .init()
  ) async throws -> GraphicsRenderResult<[RasterImage]> {
    guard options.dpi.isFinite, options.dpi > 0 else { throw PostScriptDocumentError.invalidBoundingBox }
    let target = try rasterTarget(options: options)
    let source = programData
    let result: GraphicsRenderResult<[RasterImage]>
    if let timeout = options.timeout {
      result = try await withThrowingTaskGroup(of: GraphicsRenderResult<[RasterImage]>.self) { group in
        group.addTask {
          try await renderSource(source, target: target, options: options, environment: environment)
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw PostScriptDocumentError.timeout
        }
        guard let first = try await group.next() else { throw PostScriptDocumentError.timeout }
        group.cancelAll()
        return first
      }
    } else {
      result = try await renderSource(source, target: target, options: options, environment: environment)
    }
    let selected = result.output.enumerated().compactMap { index, image in
      options.pages.contains(index + 1) ? image : nil
    }
    guard !selected.isEmpty else { throw PostScriptDocumentError.noPages }
    return GraphicsRenderResult(context: result.context, output: selected)
  }

  /// Renders raster pages incrementally through `sink` without retaining prior pages.
  public func renderRaster<Sink: RasterPageSink>(
    to sink: Sink,
    options: PostScriptDocumentRenderOptions = .init(),
    environment: InterpreterEnvironment = .init()
  ) async throws -> GraphicsRenderResult<Sink.Session.Output> {
    guard options.dpi.isFinite, options.dpi > 0 else { throw PostScriptDocumentError.invalidBoundingBox }
    let geometry = try rasterGeometry(options: options)
    let target = RasterPageSinkTarget(
      pixelWidth: geometry.width,
      pixelHeight: geometry.height,
      deviceDescriptor: geometry.descriptor,
      background: options.background.raster,
      pageDeviceMode: geometry.mode,
      sink: sink
    )
    if metadata.kind == .encapsulatedPostScript, let bounds = metadata.bounds {
      return try await Interpreter.renderEncapsulated(
        file: usesStagedStandardInput ? nil : DataFile(data: programData, mode: .read),
        bounds: bounds.graphics,
        strict: options.strict,
        to: target,
        environment: environment
      )
    }
    if usesStagedStandardInput {
      return try await Interpreter.renderStandardInput(to: target, environment: environment)
    }
    return try await Interpreter.render(
      file: DataFile(data: programData, mode: .read),
      to: target,
      environment: environment
    )
  }

  private func rasterTarget(options: PostScriptDocumentRenderOptions) throws -> RasterImageTarget {
    let geometry = try rasterGeometry(options: options)
    return RasterImageTarget(
      pixelWidth: geometry.width,
      pixelHeight: geometry.height,
      deviceDescriptor: geometry.descriptor,
      background: options.background.raster,
      pageDeviceMode: geometry.mode
    )
  }

  private func rasterGeometry(
    options: PostScriptDocumentRenderOptions
  ) throws -> (width: Int, height: Int, descriptor: GraphicsDeviceDescriptor, mode: GraphicsPageDeviceMode) {
    guard metadata.kind == .encapsulatedPostScript, options.cropMode != .media, let bounds = metadata.bounds else {
      let scale = options.dpi / 72
      let width = max(1, Int((612 * scale).rounded()))
      let height = max(1, Int((792 * scale).rounded()))
      let media = GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))
      return (width, height, GraphicsDeviceDescriptor(
        mediaBounds: media,
        imageableBounds: media,
        horizontalResolution: options.dpi,
        verticalResolution: options.dpi,
        defaultMatrix: .init(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: 0)
      ), .adaptivePageSize)
    }
    let scale = options.dpi / 72
    let minimumX = floor(bounds.lowerX * scale)
    let minimumY = floor(bounds.lowerY * scale)
    let maximumX = ceil(bounds.upperX * scale)
    let maximumY = ceil(bounds.upperY * scale)
    let width = max(1, Int(maximumX - minimumX))
    let height = max(1, Int(maximumY - minimumY))
    let media = GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))
    let descriptor = GraphicsDeviceDescriptor(
      mediaBounds: media,
      imageableBounds: media,
      horizontalResolution: options.dpi,
      verticalResolution: options.dpi,
      defaultMatrix: GraphicsMatrix(a: scale, b: 0, c: 0, d: scale, tx: -minimumX, ty: -minimumY)
    )
    return (width, height, descriptor, .fixed)
  }

  private func renderSource(
    _ source: Data,
    target: RasterImageTarget,
    options: PostScriptDocumentRenderOptions,
    environment: InterpreterEnvironment
  ) async throws -> GraphicsRenderResult<[RasterImage]> {
    if metadata.kind == .encapsulatedPostScript, let bounds = metadata.bounds {
      return try await Interpreter.renderEncapsulated(
        file: usesStagedStandardInput ? nil : DataFile(data: source, mode: .read),
        bounds: bounds.graphics,
        strict: options.strict,
        to: target,
        environment: environment
      )
    }
    if usesStagedStandardInput {
      return try await Interpreter.renderStandardInput(to: target, environment: environment)
    }
    return try await Interpreter.render(
      file: DataFile(data: source, mode: .read),
      to: target,
      environment: environment
    )
  }
}

private extension PostScriptDocumentBounds {
  var graphics: GraphicsRect {
    GraphicsRect(x: lowerX, y: lowerY, width: width, height: height)
  }
}

private extension PostScriptDocumentBackground {
  var raster: RasterColor {
    switch self {
    case .white: .white
    case .transparent: .init(red: 0, green: 0, blue: 0, alpha: 0)
    case .rgba(let red, let green, let blue, let alpha):
      .init(
        red: Double(red) / 255,
        green: Double(green) / 255,
        blue: Double(blue) / 255,
        alpha: Double(alpha) / 255
      )
    }
  }
}
