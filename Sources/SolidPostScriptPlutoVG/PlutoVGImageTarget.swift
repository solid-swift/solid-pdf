import CPlutoVG
import Foundation
import SolidPostScript

/// A portable PostScript graphics target that rasterizes pages through PlutoVG.
public struct PlutoVGImageTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = RasterImage
  public typealias Output = [RasterImage]

  /// The renderer dedicated to one PlutoVG image render.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RasterImage
    public typealias Output = [RasterImage]

    /// Images transmitted by `showpage` so far.
    public private(set) var pages: [RasterImage] = []

    private enum Lifecycle {
      case active
      case finished
      case aborted
    }

    private static let maximumBitmapBytes = 512 * 1_024 * 1_024
    private static let maximumDimension = (1 << 15) - 1

    private let pixelWidth: Int
    private let pixelHeight: Int
    private let descriptor: GraphicsDeviceDescriptor
    private let rasterMatrix: GraphicsMatrix
    private var surface: OpaquePointer?
    private var canvas: OpaquePointer?
    private var lifecycle = Lifecycle.active

    fileprivate init(
      pixelWidth: Int,
      pixelHeight: Int,
      descriptor: GraphicsDeviceDescriptor
    ) throws {
      try Self.validate(pixelWidth: pixelWidth, pixelHeight: pixelHeight, descriptor: descriptor)
      self.pixelWidth = pixelWidth
      self.pixelHeight = pixelHeight
      self.descriptor = descriptor
      self.rasterMatrix = GraphicsMatrix(
        a: 1,
        b: 0,
        c: 0,
        d: -1,
        tx: -descriptor.mediaBounds.x,
        ty: descriptor.mediaBounds.maxY
      )
      (surface, canvas) = try Self.makePage(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    deinit {
      releasePage()
    }

    /// Processes one graphics event using its authoritative state snapshots.
    public func process(_ event: GraphicsEvent) throws {
      guard lifecycle == .active, let canvas else { throw SolidPostScript.Error.ioError }
      switch event.operation {
      case .paint(.erasePage):
        try erasePage(in: canvas)
      case .paint(.fill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before, in: canvas)
      case .paint(.stroke):
        try stroke(event.before.path, state: event.before, in: canvas)
      case .page(.show):
        try showPage()
      default:
        break
      }
    }

    /// Completes the render and discards the current untransmitted page.
    public func finish() throws -> sending [RasterImage] {
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      lifecycle = .finished
      releasePage()
      let output = pages
      pages.removeAll()
      return output
    }

    /// Abandons the current page and all transmitted output.
    public func abort() {
      guard lifecycle == .active else { return }
      lifecycle = .aborted
      releasePage()
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
        pixelWidth <= maximumDimension,
        pixelHeight <= maximumDimension,
        pixelWidth <= Int.max / 4,
        pixelHeight <= Int.max / (pixelWidth * 4),
        pixelHeight <= maximumBitmapBytes / (pixelWidth * 4),
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
        matrix.a.isFinite,
        matrix.b.isFinite,
        matrix.c.isFinite,
        matrix.d.isFinite,
        matrix.tx.isFinite,
        matrix.ty.isFinite
      else {
        throw SolidPostScript.Error.configurationError
      }
    }

    private static func makePage(
      pixelWidth: Int,
      pixelHeight: Int
    ) throws -> (surface: OpaquePointer, canvas: OpaquePointer) {
      guard let surface = plutovg_surface_create(Int32(pixelWidth), Int32(pixelHeight)) else {
        throw SolidPostScript.Error.ioError
      }
      guard let canvas = plutovg_canvas_create(surface) else {
        plutovg_surface_destroy(surface)
        throw SolidPostScript.Error.ioError
      }
      var white = plutovg_color_t(r: 1, g: 1, b: 1, a: 1)
      plutovg_surface_clear(surface, &white)
      return (surface, canvas)
    }

    private func releasePage() {
      if let canvas {
        plutovg_canvas_destroy(canvas)
        self.canvas = nil
      }
      if let surface {
        plutovg_surface_destroy(surface)
        self.surface = nil
      }
    }

    private func showPage() throws {
      guard let surface else { throw SolidPostScript.Error.ioError }
      let image = try snapshot(surface)
      let next = try Self.makePage(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
      releasePage()
      self.surface = next.surface
      self.canvas = next.canvas
      pages.append(image)
    }

    private func snapshot(_ surface: OpaquePointer) throws -> RasterImage {
      let width = Int(plutovg_surface_get_width(surface))
      let height = Int(plutovg_surface_get_height(surface))
      let bytesPerRow = Int(plutovg_surface_get_stride(surface))
      guard width == pixelWidth,
        height == pixelHeight,
        bytesPerRow >= width * 4,
        height <= Int.max / bytesPerRow,
        let source = plutovg_surface_get_data(surface)
      else {
        throw SolidPostScript.Error.ioError
      }
      var data = Data(bytes: source, count: bytesPerRow * height)
      data.withUnsafeMutableBytes { bytes in
        guard let baseAddress = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        plutovg_convert_argb_to_rgba(
          baseAddress,
          baseAddress,
          Int32(width),
          Int32(height),
          Int32(bytesPerRow)
        )
      }
      return RasterImage(
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        pixelFormat: .rgba8Unorm,
        data: data
      )
    }

    private func erasePage(in canvas: OpaquePointer) throws {
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try setMatrix(rasterMatrix, in: canvas)
      try clipToImageableBounds(in: canvas)
      plutovg_canvas_set_rgb(canvas, 1, 1, 1)
      try addRect(descriptor.mediaBounds, to: canvas)
      plutovg_canvas_fill(canvas)
    }

    private func fill(
      _ path: GraphicsPath,
      rule: GraphicsFillRule,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try replay(state.clip, in: canvas)
      try setMatrix(rasterMatrix, in: canvas)
      try add(path, to: canvas)
      setFillRule(rule, in: canvas)
      try setPaint(state.paint, in: canvas)
      plutovg_canvas_fill(canvas)
    }

    private func stroke(
      _ path: GraphicsPath,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      guard let inverse = state.matrix.inverted else { return }
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try replay(state.clip, in: canvas)
      try setMatrix(state.matrix.concatenated(with: rasterMatrix), in: canvas)
      try add(path.transformed(by: inverse), to: canvas)
      try setPaint(state.paint, in: canvas)
      plutovg_canvas_set_line_width(canvas, try float(state.lineWidth))
      plutovg_canvas_set_line_cap(canvas, state.lineCap.plutoVG)
      plutovg_canvas_set_line_join(canvas, state.lineJoin.plutoVG)
      plutovg_canvas_set_miter_limit(canvas, try float(state.miterLimit))
      let dashes = try state.dash.pattern.map(float)
      try dashes.withUnsafeBufferPointer { buffer in
        plutovg_canvas_set_dash(
          canvas,
          try float(state.dash.phase),
          buffer.baseAddress,
          Int32(buffer.count)
        )
      }
      plutovg_canvas_stroke(canvas)
    }

    private func replay(_ clip: GraphicsClip, in canvas: OpaquePointer) throws {
      try setMatrix(rasterMatrix, in: canvas)
      try addRect(clip.imageableBounds, to: canvas)
      plutovg_canvas_clip(canvas)
      for constraint in clip.constraints {
        try add(constraint.path, to: canvas)
        setFillRule(constraint.rule, in: canvas)
        plutovg_canvas_clip(canvas)
      }
    }

    private func clipToImageableBounds(in canvas: OpaquePointer) throws {
      try addRect(descriptor.imageableBounds, to: canvas)
      plutovg_canvas_clip(canvas)
    }

    private func addRect(_ rect: GraphicsRect, to canvas: OpaquePointer) throws {
      plutovg_canvas_new_path(canvas)
      plutovg_canvas_rect(
        canvas,
        try float(rect.x),
        try float(rect.y),
        try float(rect.width),
        try float(rect.height)
      )
    }

    private func add(_ path: GraphicsPath, to canvas: OpaquePointer) throws {
      guard let nativePath = plutovg_path_create() else { throw SolidPostScript.Error.ioError }
      defer { plutovg_path_destroy(nativePath) }
      for element in path.elements {
        switch element {
        case .move(let point):
          plutovg_path_move_to(nativePath, try float(point.x), try float(point.y))
        case .line(let point):
          plutovg_path_line_to(nativePath, try float(point.x), try float(point.y))
        case .curve(let control1, let control2, let end):
          plutovg_path_cubic_to(
            nativePath,
            try float(control1.x),
            try float(control1.y),
            try float(control2.x),
            try float(control2.y),
            try float(end.x),
            try float(end.y)
          )
        case .close:
          plutovg_path_close(nativePath)
        }
      }
      plutovg_canvas_new_path(canvas)
      plutovg_canvas_add_path(canvas, nativePath)
    }

    private func setPaint(_ paint: GraphicsPaint, in canvas: OpaquePointer) throws {
      switch paint {
      case .deviceGray(let gray):
        let component = try float(gray)
        plutovg_canvas_set_rgb(canvas, component, component, component)
      }
    }

    private func setFillRule(_ rule: GraphicsFillRule, in canvas: OpaquePointer) {
      plutovg_canvas_set_fill_rule(canvas, rule.plutoVG)
    }

    private func setMatrix(_ matrix: GraphicsMatrix, in canvas: OpaquePointer) throws {
      var native = plutovg_matrix_t(
        a: try float(matrix.a),
        b: try float(matrix.b),
        c: try float(matrix.c),
        d: try float(matrix.d),
        e: try float(matrix.tx),
        f: try float(matrix.ty)
      )
      plutovg_canvas_set_matrix(canvas, &native)
    }

    private func float(_ value: Double) throws -> Float {
      let result = Float(value)
      guard result.isFinite else { throw SolidPostScript.Error.ioError }
      return result
    }
  }

  /// The device geometry and default transformation used for each page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The page width in pixels.
  public let pixelWidth: Int
  /// The page height in pixels.
  public let pixelHeight: Int

  /// Creates an RGBA bitmap target with explicit pixel geometry and resolution.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    resolution: Double = 72,
    imageableBounds: GraphicsRect? = nil
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    let mediaBounds = GraphicsRect(x: 0, y: 0, width: Double(pixelWidth), height: Double(pixelHeight))
    self.deviceDescriptor = GraphicsDeviceDescriptor(
      mediaBounds: mediaBounds,
      imageableBounds: imageableBounds ?? mediaBounds,
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
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    deviceDescriptor: GraphicsDeviceDescriptor
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.deviceDescriptor = deviceDescriptor
  }

  /// Creates a renderer dedicated to one render operation.
  public func makeRenderer() throws -> sending Renderer {
    try Renderer(pixelWidth: pixelWidth, pixelHeight: pixelHeight, descriptor: deviceDescriptor)
  }
}

private extension GraphicsFillRule {
  var plutoVG: plutovg_fill_rule_t {
    switch self {
    case .winding: PLUTOVG_FILL_RULE_NON_ZERO
    case .evenOdd: PLUTOVG_FILL_RULE_EVEN_ODD
    }
  }
}

private extension GraphicsLineCap {
  var plutoVG: plutovg_line_cap_t {
    switch self {
    case .butt: PLUTOVG_LINE_CAP_BUTT
    case .round: PLUTOVG_LINE_CAP_ROUND
    case .square: PLUTOVG_LINE_CAP_SQUARE
    }
  }
}

private extension GraphicsLineJoin {
  var plutoVG: plutovg_line_join_t {
    switch self {
    case .miter: PLUTOVG_LINE_JOIN_MITER
    case .round: PLUTOVG_LINE_JOIN_ROUND
    case .bevel: PLUTOVG_LINE_JOIN_BEVEL
    }
  }
}

private extension GraphicsPath {
  func transformed(by matrix: GraphicsMatrix) -> Self {
    Self(elements: elements.map { element in
      switch element {
      case .move(let point):
        .move(to: matrix.transform(point))
      case .line(let point):
        .line(to: matrix.transform(point))
      case .curve(let control1, let control2, let end):
        .curve(
          control1: matrix.transform(control1),
          control2: matrix.transform(control2),
          end: matrix.transform(end)
        )
      case .close:
        .close
      }
    })
  }
}
