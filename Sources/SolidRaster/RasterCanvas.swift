import Foundation

/// A uniquely owned CPU raster surface.
public struct RasterCanvas: ~Copyable {
  /// The surface width in pixels.
  public let width: Int
  /// The surface height in pixels.
  public let height: Int

  private let limits: RasterLimits
  private var pixels: [UInt8]
  private var clip: RasterClip
  private var compiledClip: [CoverageSpan]?
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
    var initialPixels = [UInt8](repeating: 0, count: width * height * 4)
    initialPixels.withUnsafeMutableBufferPointer { buffer in
      var span = MutableSpan(_unsafeStart: buffer.baseAddress!, count: buffer.count)
      RasterCompositor.clear(color, pixels: &span)
    }
    self.width = width
    self.height = height
    self.limits = limits
    pixels = initialPixels
    clip = RasterClip(imageableBounds: RasterRect(x: 0, y: 0, width: Double(width), height: Double(height)))
    compiledClip = nil
    finished = false
  }

  /// Replaces the ordered clipping region used by subsequent operations.
  public mutating func setClip(_ clip: RasterClip) throws(RasterError) {
    try requireActive()
    guard clip.constraints.count <= limits.maximumClipConstraints else { throw .limitExceeded }
    self.clip = clip
    compiledClip = nil
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
    let pathSpans = try GrayRasterizer.rasterize(
      path,
      rule: rule,
      width: width,
      height: height,
      limits: limits
    )
    let visible = CoverageSpans.intersect(pathSpans, try clippingSpans())
    guard case .solid(let color) = paint else { return }
    let source = try RasterCompositor.premultiplied(color)
    let surfaceWidth = width
    withPixels { span in
      RasterCompositor.composite(source, spans: visible, width: surfaceWidth, pixels: &span)
    }
  }

  /// Consumes the canvas and returns an immutable top-left-origin image.
  public consuming func finish(
    pixelFormat: RasterPixelFormat = .rgba8Unorm
  ) throws(RasterError) -> RasterImage {
    guard !finished else { throw .finishedCanvas }
    finished = true
    var output = pixels
    if pixelFormat == .rgba8Unorm {
      unpremultiply(&output)
    }
    return try RasterImage(
      width: width,
      height: height,
      bytesPerRow: width * 4,
      pixelFormat: pixelFormat,
      data: Data(output)
    )
  }

  private mutating func clippingSpans() throws(RasterError) -> [CoverageSpan] {
    if let compiledClip { return compiledClip }
    var spans = CoverageSpans.rectangle(clip.imageableBounds, width: width, height: height)
    for constraint in clip.constraints {
      let constraintSpans = try GrayRasterizer.rasterize(
        constraint.path,
        rule: constraint.rule,
        width: width,
        height: height,
        limits: limits
      )
      spans = CoverageSpans.intersect(spans, constraintSpans)
      if spans.isEmpty { break }
    }
    compiledClip = spans
    return spans
  }

  private borrowing func requireActive() throws(RasterError) {
    guard !finished else { throw .finishedCanvas }
  }

  private mutating func withPixels(
    _ body: (inout MutableSpan<UInt8>) -> Void
  ) {
    pixels.withUnsafeMutableBufferPointer { buffer in
      var span = MutableSpan(_unsafeStart: buffer.baseAddress!, count: buffer.count)
      body(&span)
    }
  }

  private func unpremultiply(_ bytes: inout [UInt8]) {
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
