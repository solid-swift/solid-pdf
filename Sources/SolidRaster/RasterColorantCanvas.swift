import Foundation

/// A uniquely owned bounded surface containing one gray8 plane per device colorant.
public struct RasterColorantCanvas: ~Copyable {
  public let width: Int
  public let height: Int
  public let colorants: [String]

  private let limits: RasterLimits
  private var planes: [Data]
  private var clip: RasterClip
  private var compiledClip: [CoverageSpan]
  private var visibleSpans: [CoverageSpan]
  private var finished = false

  /// Creates empty colorant planes in the supplied order.
  public init(
    width: Int,
    height: Int,
    colorants: [String],
    limits: RasterLimits = .default
  ) throws(RasterError) {
    let planeBytes = width.multipliedReportingOverflow(by: height)
    let totalBytes = planeBytes.partialValue.multipliedReportingOverflow(by: colorants.count)
    guard width > 0, height > 0, !colorants.isEmpty,
      Set(colorants).count == colorants.count,
      !planeBytes.overflow, !totalBytes.overflow,
      totalBytes.partialValue <= limits.maximumSurfaceBytes
    else { throw .limitExceeded }
    self.width = width
    self.height = height
    self.colorants = colorants
    self.limits = limits
    planes = colorants.map { _ in Data(repeating: 0, count: planeBytes.partialValue) }
    clip = RasterClip(imageableBounds: RasterRect(x: 0, y: 0, width: Double(width), height: Double(height)))
    compiledClip = []
    visibleSpans = []
  }

  /// Replaces the clipping region used by subsequent operations.
  public mutating func setClip(_ clip: RasterClip) throws(RasterError) {
    try requireActive()
    guard clip.constraints.count <= limits.maximumClipConstraints else { throw .limitExceeded }
    self.clip = clip
    compiledClip.removeAll(keepingCapacity: true)
  }

  /// Clears every colorant plane to zero tint.
  public mutating func clear() throws(RasterError) {
    try requireActive()
    for index in planes.indices { planes[index].resetBytes(in: planes[index].indices) }
  }

  /// Fills a path using subtractive colorant and overprint semantics.
  public mutating func fill(
    _ path: RasterPath,
    rule: RasterFillRule,
    paint: RasterColorantPaint
  ) throws(RasterError) {
    try requireActive()
    guard path.elements.count <= limits.maximumPathElements else { throw .limitExceeded }
    guard !paint.paintsNothing else { return }
    let pathSpans = try rasterize(path, rule: rule)
    try compileClip()
    var visible: [CoverageSpan] = []
    swap(&visible, &visibleSpans)
    CoverageSpans.intersect(pathSpans.span, compiledClip.span, into: &visible)
    swap(&visibleSpans, &visible)
    let spans = visibleSpans
    let surfaceWidth = width
    for (index, name) in colorants.enumerated() {
      guard let tint = paint.tints[name] ?? (paint.overprintsUnspecifiedColorants ? nil : 0) else { continue }
      Self.composite(tint: tint, spans: spans.span, width: surfaceWidth, into: &planes[index])
    }
  }

  /// Strokes a path using the shared native stroker.
  public mutating func stroke(
    _ path: RasterPath,
    style: RasterStrokeStyle,
    paint: RasterColorantPaint,
    transform: RasterAffineTransform = .identity
  ) throws(RasterError) {
    try fill(
      PathStroker.stroke(path, style: style, transform: transform),
      rule: .winding,
      paint: paint
    )
  }

  /// Consumes the canvas and returns immutable planes in device order.
  public consuming func finish() throws(RasterError) -> [RasterColorantPlane] {
    guard !finished else { throw .finishedCanvas }
    finished = true
    var result: [RasterColorantPlane] = []
    result.reserveCapacity(colorants.count)
    for (name, data) in zip(colorants, planes) {
      result.append(RasterColorantPlane(
        name: name,
        mask: try RasterMask(width: width, height: height, bytesPerRow: width, data: data)
      ))
    }
    planes.removeAll()
    return result
  }

  private mutating func compileClip() throws(RasterError) {
    guard compiledClip.isEmpty else { return }
    CoverageSpans.rectangle(clip.imageableBounds, width: width, height: height, into: &compiledClip)
    for constraint in clip.constraints where !compiledClip.isEmpty {
      let constraintSpans = try rasterize(constraint.path, rule: constraint.rule)
      var intersection: [CoverageSpan] = []
      CoverageSpans.intersect(compiledClip.span, constraintSpans.span, into: &intersection)
      compiledClip = intersection
    }
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

  private static func composite(
    tint: Double,
    spans: borrowing Span<CoverageSpan>,
    width: Int,
    into data: inout Data
  ) {
    let source = UInt16((min(1, max(0, tint)) * 255).rounded())
    data.withUnsafeMutableBytes { buffer in
      let bytes = buffer.bindMemory(to: UInt8.self)
      for index in 0..<spans.count {
        let span = spans[index]
        let coverage = UInt16(span.coverage)
        for x in span.x..<(span.x + span.length) {
          let offset = span.y * width + x
          let destination = UInt16(bytes[offset])
          bytes[offset] = UInt8((destination * (255 - coverage) + source * coverage + 127) / 255)
        }
      }
    }
  }

  private borrowing func requireActive() throws(RasterError) {
    guard !finished else { throw .finishedCanvas }
  }
}
