import Foundation
import SolidPostScript
import SolidRaster

/// A portable PostScript graphics target backed entirely by native Swift rasterization.
public struct RasterImageTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = RasterImage
  public typealias Output = [RasterImage]

  /// A renderer dedicated to one native raster job.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RasterImage
    public typealias Output = [RasterImage]

    /// Images transmitted by page operations so far.
    public private(set) var pages: [RasterImage] = []

    private enum Lifecycle {
      case active
      case finished
      case aborted
    }

    private let pixelWidth: Int
    private let pixelHeight: Int
    private let descriptor: GraphicsDeviceDescriptor
    private let rasterMatrix: GraphicsMatrix
    private var canvas: RasterCanvas?
    private var lifecycle = Lifecycle.active
    private var activeImage: (descriptor: GraphicsImageDescriptor, state: GraphicsStateSnapshot, components: [Float])?

    fileprivate init(pixelWidth: Int, pixelHeight: Int, descriptor: GraphicsDeviceDescriptor) throws {
      try Self.validate(pixelWidth: pixelWidth, pixelHeight: pixelHeight, descriptor: descriptor)
      self.pixelWidth = pixelWidth
      self.pixelHeight = pixelHeight
      self.descriptor = descriptor
      rasterMatrix = GraphicsMatrix(
        a: 1,
        b: 0,
        c: 0,
        d: -1,
        tx: -descriptor.mediaBounds.x,
        ty: descriptor.mediaBounds.maxY
      )
      canvas = try Self.makePage(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    /// Processes one validated graphics event.
    public func process(_ event: GraphicsEvent) throws {
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      switch event.operation {
      case .paint(.erasePage):
        try erasePage()
      case .paint(.fill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before)
      case .paint(.stroke):
        try stroke(event.before.path, matrix: event.before.matrix, state: event.before)
      case .paint(.fillRectangles(let paths)):
        try fill(GraphicsPath(elements: paths.flatMap(\.elements)), rule: .winding, state: event.before)
      case .paint(.strokeRectangles(let paths, let matrix)):
        let effectiveMatrix = matrix?.concatenated(with: event.before.matrix) ?? event.before.matrix
        try stroke(
          GraphicsPath(elements: paths.flatMap(\.elements)),
          matrix: effectiveMatrix,
          state: event.before
        )
      case .page(.show), .page(.copy):
        try transmitPage()
      default:
        break
      }
    }

    /// Begins one sampled-image transfer.
    public func beginImage(_ event: GraphicsEvent) throws {
      guard lifecycle == .active,
        activeImage == nil,
        case .paint(.image(let descriptor)) = event.operation
      else { throw SolidPostScript.Error.ioError }
      activeImage = (descriptor, event.before, [])
    }

    /// Receives complete sampled-image rows in order.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard var image = activeImage else { throw SolidPostScript.Error.ioError }
      let rowWidth = image.descriptor.width * image.descriptor.kind.componentCount
      guard rowWidth > 0,
        rows.startRow == image.components.count / rowWidth,
        rows.rowCount <= Int.max / rowWidth,
        rows.components.count == rows.rowCount * rowWidth
      else { throw SolidPostScript.Error.ioError }
      image.components.append(contentsOf: rows.components)
      activeImage = image
    }

    /// Validates and paints the active sampled image.
    public func endImage() throws {
      guard let image = activeImage, lifecycle == .active else { throw SolidPostScript.Error.ioError }
      activeImage = nil
      try draw(GraphicsImage(descriptor: image.descriptor, components: image.components), state: image.state)
    }

    /// Abandons the active sampled image.
    public func abortImage() {
      activeImage = nil
    }

    /// Completes the render and discards its untransmitted page.
    public func finish() throws -> sending [RasterImage] {
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      lifecycle = .finished
      activeImage = nil
      canvas = nil
      let output = pages
      pages.removeAll()
      return output
    }

    /// Abandons the render and all transmitted output.
    public func abort() {
      guard lifecycle == .active else { return }
      lifecycle = .aborted
      activeImage = nil
      canvas = nil
      pages.removeAll()
    }

    private static func validate(
      pixelWidth: Int,
      pixelHeight: Int,
      descriptor: GraphicsDeviceDescriptor
    ) throws {
      let media = descriptor.mediaBounds
      let imageable = descriptor.imageableBounds
      let matrix = descriptor.defaultMatrix
      guard pixelWidth > 0,
        pixelHeight > 0,
        pixelWidth <= Int.max / 4,
        pixelHeight <= Int.max / (pixelWidth * 4),
        pixelHeight <= RasterLimits.default.maximumSurfaceBytes / (pixelWidth * 4),
        media.x.isFinite,
        media.y.isFinite,
        media.width == Double(pixelWidth),
        media.height == Double(pixelHeight),
        imageable.x.isFinite,
        imageable.y.isFinite,
        imageable.width.isFinite,
        imageable.height.isFinite,
        imageable.width >= 0,
        imageable.height >= 0,
        imageable.x >= media.x,
        imageable.y >= media.y,
        imageable.maxX <= media.maxX,
        imageable.maxY <= media.maxY,
        descriptor.horizontalResolution.isFinite,
        descriptor.verticalResolution.isFinite,
        descriptor.horizontalResolution > 0,
        descriptor.verticalResolution > 0,
        [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].allSatisfy(\.isFinite)
      else { throw SolidPostScript.Error.configurationError }
    }

    private static func makePage(pixelWidth: Int, pixelHeight: Int) throws -> RasterCanvas {
      do {
        return try RasterCanvas(width: pixelWidth, height: pixelHeight)
      } catch {
        throw SolidPostScript.Error.ioError
      }
    }

    private func withCanvas(_ body: (inout RasterCanvas) throws -> Void) throws {
      guard lifecycle == .active, var current = canvas.take() else {
        throw SolidPostScript.Error.ioError
      }
      do {
        try body(&current)
        canvas = consume current
      } catch {
        canvas = consume current
        if error is RasterError { throw SolidPostScript.Error.ioError }
        throw error
      }
    }

    private func fill(_ path: GraphicsPath, rule: GraphicsFillRule, state: GraphicsStateSnapshot) throws {
      let transformed = path.transformed(by: rasterMatrix).rasterPath
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(state.clip))
        try canvas.fill(transformed, rule: rule.raster, paint: state.paint.raster)
      }
    }

    private func stroke(
      _ path: GraphicsPath,
      matrix: GraphicsMatrix,
      state: GraphicsStateSnapshot
    ) throws {
      guard let inverse = matrix.inverted else { return }
      let strokeTransform = matrix.concatenated(with: rasterMatrix).raster
      let style = RasterStrokeStyle(
        width: state.lineWidth,
        cap: state.lineCap.raster,
        join: state.lineJoin.raster,
        miterLimit: state.miterLimit,
        dash: state.dash.pattern,
        dashPhase: state.dash.phase
      )
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(state.clip))
        try canvas.stroke(
          path.transformed(by: inverse).rasterPath,
          style: style,
          paint: state.paint.raster,
          transform: strokeTransform
        )
      }
    }

    private func erasePage() throws {
      let clip = GraphicsClip(imageableBounds: descriptor.imageableBounds)
      let mediaPath = GraphicsPath.rectangle(descriptor.mediaBounds).transformed(by: rasterMatrix).rasterPath
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(clip))
        try canvas.fill(mediaPath, rule: .winding, paint: .solid(.white))
      }
    }

    private func draw(_ image: GraphicsImage, state: GraphicsStateSnapshot) throws {
      let descriptor = image.descriptor
      let rowWidth = descriptor.width * descriptor.kind.componentCount
      let renderedHeight = rowWidth == 0 ? 0 : image.components.count / rowWidth
      guard descriptor.width > 0,
        renderedHeight > 0,
        renderedHeight <= descriptor.height,
        image.components.count == renderedHeight * rowWidth
      else { return }
      let rasterImage: RasterImage
      do {
        rasterImage = try RasterImage(
          width: descriptor.width,
          height: renderedHeight,
          bytesPerRow: descriptor.width * 4,
          pixelFormat: .rgba8UnormPremultiplied,
          data: image.premultipliedRGBA8()
        )
      } catch {
        throw SolidPostScript.Error.ioError
      }
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(state.clip))
        try canvas.draw(
          rasterImage,
          transform: descriptor.imageToDevice.concatenated(with: rasterMatrix).raster,
          interpolation: descriptor.interpolate ? .linear : .nearest
        )
      }
    }

    private func transmitPage() throws {
      guard let current = canvas.take() else { throw SolidPostScript.Error.ioError }
      do {
        let image = try current.finish()
        let next = try Self.makePage(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        canvas = consume next
        pages.append(image)
      } catch {
        canvas = nil
        if error is RasterError { throw SolidPostScript.Error.ioError }
        throw error
      }
    }

    private func rasterClip(_ clip: GraphicsClip) throws(RasterError) -> RasterClip {
      RasterClip(
        imageableBounds: transformedBounds(clip.imageableBounds, by: rasterMatrix).raster,
        constraints: clip.constraints.map {
          RasterClipConstraint(
            path: $0.path.transformed(by: rasterMatrix).rasterPath,
            rule: $0.rule.raster
          )
        }
      )
    }

    private func transformedBounds(_ rect: GraphicsRect, by matrix: GraphicsMatrix) -> GraphicsRect {
      let points = [
        GraphicsPoint(x: rect.x, y: rect.y),
        GraphicsPoint(x: rect.maxX, y: rect.y),
        GraphicsPoint(x: rect.maxX, y: rect.maxY),
        GraphicsPoint(x: rect.x, y: rect.maxY),
      ].map(matrix.transform)
      let xs = points.map(\.x)
      let ys = points.map(\.y)
      let minimumX = xs.min() ?? 0
      let maximumX = xs.max() ?? 0
      let minimumY = ys.min() ?? 0
      let maximumY = ys.max() ?? 0
      return GraphicsRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
    }
  }

  /// Device geometry used for each page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// Page width in pixels.
  public let pixelWidth: Int
  /// Page height in pixels.
  public let pixelHeight: Int

  /// Creates the installation-default Letter target at 72 dots per inch.
  public init() {
    self.init(pixelWidth: 612, pixelHeight: 792)
  }

  /// Creates a bitmap target with explicit pixel geometry and resolution.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    resolution: Double = 72,
    imageableBounds: GraphicsRect? = nil
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    let media = GraphicsRect(x: 0, y: 0, width: Double(pixelWidth), height: Double(pixelHeight))
    deviceDescriptor = GraphicsDeviceDescriptor(
      mediaBounds: media,
      imageableBounds: imageableBounds ?? media,
      horizontalResolution: resolution,
      verticalResolution: resolution,
      defaultMatrix: GraphicsMatrix(
        a: resolution / 72,
        b: 0,
        c: 0,
        d: resolution / 72,
        tx: 0,
        ty: 0
      )
    )
  }

  /// Creates a bitmap target using an explicit PostScript device descriptor.
  public init(pixelWidth: Int, pixelHeight: Int, deviceDescriptor: GraphicsDeviceDescriptor) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.deviceDescriptor = deviceDescriptor
  }

  /// Creates a renderer dedicated to one render.
  public func makeRenderer() throws -> sending Renderer {
    try Renderer(pixelWidth: pixelWidth, pixelHeight: pixelHeight, descriptor: deviceDescriptor)
  }
}

private extension GraphicsMatrix {
  var raster: RasterAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

private extension GraphicsRect {
  var raster: RasterRect { .init(x: x, y: y, width: width, height: height) }
}

private extension GraphicsPath {
  var rasterPath: RasterPath {
    RasterPath(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: RasterPoint(x: point.x, y: point.y))
      case .line(let point): .line(to: RasterPoint(x: point.x, y: point.y))
      case .curve(let control1, let control2, let end):
        .cubic(
          control1: RasterPoint(x: control1.x, y: control1.y),
          control2: RasterPoint(x: control2.x, y: control2.y),
          end: RasterPoint(x: end.x, y: end.y)
        )
      case .close: .close
      }
    })
  }

  static func rectangle(_ rect: GraphicsRect) -> Self {
    Self(elements: [
      .move(to: GraphicsPoint(x: rect.x, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.maxY)),
      .line(to: GraphicsPoint(x: rect.x, y: rect.maxY)),
      .close,
    ])
  }

  func transformed(by matrix: GraphicsMatrix) -> Self {
    Self(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: matrix.transform(point))
      case .line(let point): .line(to: matrix.transform(point))
      case .curve(let control1, let control2, let end):
        .curve(
          control1: matrix.transform(control1),
          control2: matrix.transform(control2),
          end: matrix.transform(end)
        )
      case .close: .close
      }
    })
  }
}

private extension GraphicsFillRule {
  var raster: RasterFillRule { self == .winding ? .winding : .evenOdd }
}

private extension GraphicsLineCap {
  var raster: RasterLineCap {
    switch self {
    case .butt: .butt
    case .round: .round
    case .square: .square
    }
  }
}

private extension GraphicsLineJoin {
  var raster: RasterLineJoin {
    switch self {
    case .miter: .miter
    case .round: .round
    case .bevel: .bevel
    }
  }
}

private extension GraphicsPaint {
  var raster: RasterPaint {
    let rgb = rgbComponents
    return .solid(RasterColor(red: rgb.red, green: rgb.green, blue: rgb.blue))
  }
}
