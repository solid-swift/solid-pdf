import Foundation

/// A uniquely owned CPU raster surface.
public struct RasterCanvas: ~Copyable {
  /// The surface width in pixels.
  public let width: Int
  /// The surface height in pixels.
  public let height: Int

  private let limits: RasterLimits
  private var pixels: Data
  private var clip: RasterClip
  private var compiledClip: [CoverageSpan]
  private var compiledConstraintCount: Int?
  private var clipScratch: [CoverageSpan]
  private var visibleSpans: [CoverageSpan]
  private var finished: Bool

  /// Creates a raster canvas initialized to `background`.
  public init(
    width: Int,
    height: Int,
    background: RasterColor = .white,
    limits: RasterLimits = .default
  ) throws(RasterError) {
    guard width > 0,
      height > 0,
      width <= Int.max / 4,
      height <= Int.max / (width * 4),
      width * height * 4 <= limits.maximumSurfaceBytes
    else { throw .limitExceeded }
    let color = try RasterCompositor.premultiplied(background)
    var initialPixels = Data(count: width * height * 4)
    initialPixels.withUnsafeMutableBytes { buffer in
      var span = MutableSpan(_unsafeStart: buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), count: buffer.count)
      RasterCompositor.clear(color, pixels: &span)
    }
    self.width = width
    self.height = height
    self.limits = limits
    pixels = initialPixels
    clip = RasterClip(imageableBounds: RasterRect(x: 0, y: 0, width: Double(width), height: Double(height)))
    compiledClip = []
    compiledConstraintCount = nil
    clipScratch = []
    visibleSpans = []
    finished = false
  }

  /// Replaces the ordered clipping region used by subsequent operations.
  public mutating func setClip(_ clip: RasterClip) throws(RasterError) {
    try requireActive()
    guard clip.constraints.count <= limits.maximumClipConstraints else { throw .limitExceeded }
    guard clip != self.clip else { return }
    let canExtendCompiledPrefix = compiledConstraintCount == self.clip.constraints.count
      && self.clip.imageableBounds == clip.imageableBounds
      && self.clip.constraints.count <= clip.constraints.count
      && self.clip.constraints.elementsEqual(clip.constraints.prefix(self.clip.constraints.count))
    self.clip = clip
    if !canExtendCompiledPrefix {
      compiledConstraintCount = nil
    }
  }

  /// Clears the complete surface to a color.
  public mutating func clear(_ color: RasterColor) throws(RasterError) {
    try requireActive()
    let source = try RasterCompositor.premultiplied(color)
    withPixels { span in RasterCompositor.clear(source, pixels: &span) }
  }

  /// Fills a path using its selected interior rule and paint.
  public mutating func fill(
    _ path: RasterPath,
    rule: RasterFillRule,
    paint: RasterPaint
  ) throws(RasterError) {
    try requireActive()
    guard path.elements.count <= limits.maximumPathElements else { throw .limitExceeded }
    let pathSpans = try rasterize(path, rule: rule)
    try compileClip()
    intersectWithClip(pathSpans)
    guard case .solid(let color) = paint else { return }
    let source = try RasterCompositor.premultiplied(color)
    let surfaceWidth = width
    let visible = visibleSpans
    withPixels { span in
      RasterCompositor.composite(source, spans: visible.span, width: surfaceWidth, pixels: &span)
    }
  }

  /// Strokes a path after applying dash, cap, join, and transformation geometry.
  public mutating func stroke(
    _ path: RasterPath,
    style: RasterStrokeStyle,
    paint: RasterPaint,
    transform: RasterAffineTransform = .identity
  ) throws(RasterError) {
    try requireActive()
    let outline = try PathStroker.stroke(path, style: style, transform: transform)
    try fill(outline, rule: .winding, paint: paint)
  }

  /// Paints an ordered color-interpolated triangle mesh through the current clip.
  public mutating func paint(_ mesh: RasterGradientMesh) throws(RasterError) {
    try requireActive()
    guard mesh.triangles.count <= 1_000_000,
      mesh.triangles.count <= limits.maximumScratchBytes / MemoryLayout<RasterGradientTriangle>.stride
    else { throw .limitExceeded }
    try compileClip()
    let destinationWidth = width
    for triangle in mesh.triangles {
      let vertices = [triangle.first, triangle.second, triangle.third]
      guard vertices.allSatisfy({
        $0.position.x.isFinite && $0.position.y.isFinite
          && $0.color.red.isFinite && $0.color.green.isFinite
          && $0.color.blue.isFinite && $0.color.alpha.isFinite
      }) else { throw .invalidGeometry }
      let path = RasterPath(elements: [
        .move(to: triangle.first.position),
        .line(to: triangle.second.position),
        .line(to: triangle.third.position),
        .close,
      ])
      let spans = try rasterize(path, rule: .winding)
      intersectWithClip(spans)
      let visible = visibleSpans
      withPixels { pixels in
        RasterCompositor.compositeGradient(
          triangle,
          spans: visible.span,
          width: destinationWidth,
          pixels: &pixels
        )
      }
    }
  }

  /// Draws an image through an affine transformation and the current clip.
  public mutating func draw(
    _ image: RasterImage,
    transform: RasterAffineTransform,
    interpolation: RasterInterpolation = .nearest
  ) throws(RasterError) {
    try requireActive()
    guard let inverse = transform.inverted,
      image.width > 0,
      image.height > 0,
      image.data.count <= limits.maximumSurfaceBytes
    else { throw .invalidImage }
    let first = transform.transform(RasterPoint(x: 0, y: 0))
    let second = transform.transform(RasterPoint(x: Double(image.width), y: 0))
    let third = transform.transform(RasterPoint(x: Double(image.width), y: Double(image.height)))
    let fourth = transform.transform(RasterPoint(x: 0, y: Double(image.height)))
    let boundary = RasterPath(elements: [
      .move(to: first),
      .line(to: second),
      .line(to: third),
      .line(to: fourth),
      .close,
    ])
    let boundarySpans = try rasterize(boundary, rule: .winding)
    try compileClip()
    intersectWithClip(boundarySpans)
    let destinationWidth = width
    let visible = visibleSpans
    image.data.withUnsafeBytes { sourceBuffer in
      let source = Span(
        _unsafeStart: sourceBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
        count: sourceBuffer.count
      )
      withPixels { span in
        RasterCompositor.compositeImage(
          source: source,
          sourceWidth: image.width,
          sourceHeight: image.height,
          sourceBytesPerRow: image.bytesPerRow,
          sourceFormat: image.pixelFormat,
          inverseTransform: inverse,
          interpolation: interpolation,
          spans: visible.span,
          destinationWidth: destinationWidth,
          pixels: &span
        )
      }
    }
  }

  /// Consumes the canvas and returns an immutable top-left-origin image.
  public consuming func finish(
    pixelFormat: RasterPixelFormat = .rgba8Unorm
  ) throws(RasterError) -> RasterImage {
    guard !finished else { throw .finishedCanvas }
    finished = true
    var output = pixels
    pixels = Data()
    if pixelFormat == .rgba8Unorm {
      unpremultiply(&output)
    }
    return try RasterImage(
      width: width,
      height: height,
      bytesPerRow: width * 4,
      pixelFormat: pixelFormat,
      data: output
    )
  }

  private mutating func compileClip() throws(RasterError) {
    if compiledConstraintCount == nil {
      CoverageSpans.rectangle(clip.imageableBounds, width: width, height: height, into: &compiledClip)
      compiledConstraintCount = 0
    }
    guard var constraintIndex = compiledConstraintCount,
      constraintIndex < clip.constraints.count
    else { return }

    while constraintIndex < clip.constraints.count, !compiledClip.isEmpty {
      let constraint = clip.constraints[constraintIndex]
      let constraintSpans = try rasterize(constraint.path, rule: constraint.rule)
      var scratch: [CoverageSpan] = []
      swap(&scratch, &clipScratch)
      CoverageSpans.intersect(compiledClip.span, constraintSpans.span, into: &scratch)
      swap(&compiledClip, &scratch)
      swap(&clipScratch, &scratch)
      constraintIndex += 1
      compiledConstraintCount = constraintIndex
    }
    if compiledClip.isEmpty {
      compiledConstraintCount = clip.constraints.count
    }
  }

  private mutating func intersectWithClip(_ spans: borrowing [CoverageSpan]) {
    var result: [CoverageSpan] = []
    swap(&result, &visibleSpans)
    CoverageSpans.intersect(spans.span, compiledClip.span, into: &result)
    swap(&visibleSpans, &result)
  }

  private func rasterize(
    _ path: borrowing RasterPath,
    rule: RasterFillRule
  ) throws(RasterError) -> [CoverageSpan] {
    if let rectangle = CoverageSpans.integralRectangle(in: path) {
      var spans: [CoverageSpan] = []
      CoverageSpans.rectangle(rectangle, width: width, height: height, into: &spans)
      return spans
    }
    return try GrayRasterizer.rasterize(
      path,
      rule: rule,
      width: width,
      height: height,
      limits: limits
    )
  }

  private borrowing func requireActive() throws(RasterError) {
    guard !finished else { throw .finishedCanvas }
  }

  private mutating func withPixels(
    _ body: (inout MutableSpan<UInt8>) -> Void
  ) {
    pixels.withUnsafeMutableBytes { buffer in
      var span = MutableSpan(
        _unsafeStart: buffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
        count: buffer.count
      )
      body(&span)
    }
  }

  private func unpremultiply(_ data: inout Data) {
    data.withUnsafeMutableBytes { buffer in
      let bytes = buffer.bindMemory(to: UInt8.self)
      var offset = 0
      while offset < bytes.count {
        let alpha = UInt16(bytes[offset + 3])
        if alpha > 0, alpha < 255 {
          bytes[offset] = UInt8(min(255, (UInt16(bytes[offset]) * 255 + alpha / 2) / alpha))
          bytes[offset + 1] = UInt8(min(255, (UInt16(bytes[offset + 1]) * 255 + alpha / 2) / alpha))
          bytes[offset + 2] = UInt8(min(255, (UInt16(bytes[offset + 2]) * 255 + alpha / 2) / alpha))
        }
        offset += 4
      }
    }
  }
}
