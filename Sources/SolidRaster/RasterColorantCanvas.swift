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
    paint: RasterColorantPaint,
    deviceRendering: RasterHalftoneProgram? = nil
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
      Self.composite(
        tint: tint,
        colorant: name,
        spans: spans.span,
        width: surfaceWidth,
        deviceRendering: deviceRendering,
        into: &planes[index]
      )
    }
  }

  /// Strokes a path using the shared native stroker.
  public mutating func stroke(
    _ path: RasterPath,
    style: RasterStrokeStyle,
    paint: RasterColorantPaint,
    transform: RasterAffineTransform = .identity,
    deviceRendering: RasterHalftoneProgram? = nil
  ) throws(RasterError) {
    try fill(
      PathStroker.stroke(path, style: style, transform: transform),
      rule: .winding,
      paint: paint,
      deviceRendering: deviceRendering
    )
  }

  /// Paints a colorant-interpolated triangle mesh through the current clip.
  public mutating func paint(
    _ mesh: RasterColorantGradientMesh,
    deviceRendering: RasterHalftoneProgram? = nil
  ) throws(RasterError) {
    try requireActive()
    guard mesh.triangles.count <= 1_000_000,
      mesh.triangles.count <= limits.maximumScratchBytes / MemoryLayout<RasterColorantGradientTriangle>.stride
    else { throw .limitExceeded }
    try compileClip()
    for triangle in mesh.triangles {
      let positions = [triangle.first.position, triangle.second.position, triangle.third.position]
      guard positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw .invalidGeometry }
      let path = RasterPath(elements: [
        .move(to: triangle.first.position),
        .line(to: triangle.second.position),
        .line(to: triangle.third.position),
        .close,
      ])
      let triangleSpans = try rasterize(path, rule: .winding)
      var visible: [CoverageSpan] = []
      swap(&visible, &visibleSpans)
      CoverageSpans.intersect(triangleSpans.span, compiledClip.span, into: &visible)
      swap(&visibleSpans, &visible)
      let spans = visibleSpans
      try composite(triangle, spans: spans.span, deviceRendering: deviceRendering)
    }
  }

  /// Draws subtractive colorant planes through an affine transform and optional opacity mask.
  public mutating func draw(
    _ sourcePlanes: [RasterColorantPlane],
    transform: RasterAffineTransform,
    interpolation: RasterInterpolation = .nearest,
    mask: RasterMask? = nil,
    maskTransform: RasterAffineTransform? = nil,
    maskInterpolation: RasterInterpolation = .nearest,
    overprintsUnspecifiedColorants: Bool = false,
    deviceRendering: RasterHalftoneProgram? = nil
  ) throws(RasterError) {
    try requireActive()
    guard let inverse = transform.inverted,
      let source = sourcePlanes.first?.mask,
      source.width > 0,
      source.height > 0,
      sourcePlanes.allSatisfy({
        $0.mask.width == source.width && $0.mask.height == source.height
          && $0.mask.data.count <= limits.maximumSurfaceBytes
      })
    else { throw .invalidImage }
    let inverseMask: RasterAffineTransform?
    if let mask {
      guard let maskTransform, let inverted = maskTransform.inverted,
        mask.width > 0, mask.height > 0, mask.data.count <= limits.maximumSurfaceBytes
      else { throw .invalidImage }
      inverseMask = inverted
    } else {
      inverseMask = nil
    }

    let corners = [
      transform.transform(RasterPoint(x: 0, y: 0)),
      transform.transform(RasterPoint(x: Double(source.width), y: 0)),
      transform.transform(RasterPoint(x: Double(source.width), y: Double(source.height))),
      transform.transform(RasterPoint(x: 0, y: Double(source.height))),
    ]
    let boundary = RasterPath(elements: [
      .move(to: corners[0]), .line(to: corners[1]), .line(to: corners[2]),
      .line(to: corners[3]), .close,
    ])
    let boundarySpans = try rasterize(boundary, rule: .winding)
    try compileClip()
    var visible: [CoverageSpan] = []
    swap(&visible, &visibleSpans)
    CoverageSpans.intersect(boundarySpans.span, compiledClip.span, into: &visible)
    swap(&visibleSpans, &visible)

    let sources = Dictionary(uniqueKeysWithValues: sourcePlanes.map { ($0.name, $0.mask) })
    let spans = visibleSpans
    let destinationWidth = width
    for (planeIndex, name) in colorants.enumerated() {
      let sourceMask = sources[name]
      if sourceMask == nil, overprintsUnspecifiedColorants { continue }
      Self.compositeImage(
        sourceMask,
        inverse: inverse,
        interpolation: interpolation,
        mask: mask,
        inverseMask: inverseMask,
        maskInterpolation: maskInterpolation,
        spans: spans.span,
        colorant: name,
        overprints: overprintsUnspecifiedColorants,
        deviceRendering: deviceRendering,
        destinationWidth: destinationWidth,
        into: &planes[planeIndex]
      )
    }
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
    colorant: String,
    spans: borrowing Span<CoverageSpan>,
    width: Int,
    deviceRendering: RasterHalftoneProgram?,
    into data: inout Data
  ) {
    let base = min(1, max(0, tint))
    data.withUnsafeMutableBytes { buffer in
      let bytes = buffer.bindMemory(to: UInt8.self)
      for index in 0..<spans.count {
        let span = spans[index]
        let coverage = UInt16(span.coverage)
        for x in span.x..<(span.x + span.length) {
          let rendered = deviceRendering?.quantizeTint(
            base,
            colorant: colorant,
            x: x,
            y: span.y
          ) ?? base
          let source = UInt16((rendered * 255).rounded())
          let offset = span.y * width + x
          let destination = UInt16(bytes[offset])
          bytes[offset] = UInt8((destination * (255 - coverage) + source * coverage + 127) / 255)
        }
      }
    }
  }

  private mutating func composite(
    _ triangle: RasterColorantGradientTriangle,
    spans: borrowing Span<CoverageSpan>,
    deviceRendering: RasterHalftoneProgram?
  ) throws(RasterError) {
    let first = triangle.first.position
    let second = triangle.second.position
    let third = triangle.third.position
    let denominator = (second.y - third.y) * (first.x - third.x)
      + (third.x - second.x) * (first.y - third.y)
    guard denominator != 0, denominator.isFinite else { return }
    let paints = [triangle.first.paint, triangle.second.paint, triangle.third.paint]
    let overprints = paints.allSatisfy(\.overprintsUnspecifiedColorants)
    let targetWidth = width
    for (planeIndex, name) in colorants.enumerated() {
      let values = paints.map { $0.tints[name] }
      if overprints, values.allSatisfy({ $0 == nil }) { continue }
      let tints = values.map { $0 ?? 0 }
      planes[planeIndex].withUnsafeMutableBytes { buffer in
        let bytes = buffer.bindMemory(to: UInt8.self)
        for spanIndex in 0..<spans.count {
          let span = spans[spanIndex]
          let y = Double(span.y) + 0.5
          for x in span.x..<(span.x + span.length) {
            let centerX = Double(x) + 0.5
            let firstWeight = ((second.y - third.y) * (centerX - third.x)
              + (third.x - second.x) * (y - third.y)) / denominator
            let secondWeight = ((third.y - first.y) * (centerX - third.x)
              + (first.x - third.x) * (y - third.y)) / denominator
            let tint = tints[0] * firstWeight + tints[1] * secondWeight
              + tints[2] * (1 - firstWeight - secondWeight)
            if overprints, tint <= 0 { continue }
            let rendered = deviceRendering?.quantizeTint(tint, colorant: name, x: x, y: span.y)
              ?? min(1, max(0, tint))
            let source = UInt16((rendered * 255).rounded())
            let coverage = UInt16(span.coverage)
            let offset = span.y * targetWidth + x
            let destination = UInt16(bytes[offset])
            bytes[offset] = UInt8((destination * (255 - coverage) + source * coverage + 127) / 255)
          }
        }
      }
    }
  }

  private static func compositeImage(
    _ source: RasterMask?,
    inverse: RasterAffineTransform,
    interpolation: RasterInterpolation,
    mask: RasterMask?,
    inverseMask: RasterAffineTransform?,
    maskInterpolation: RasterInterpolation,
    spans: borrowing Span<CoverageSpan>,
    colorant: String,
    overprints: Bool,
    deviceRendering: RasterHalftoneProgram?,
    destinationWidth: Int,
    into destination: inout Data
  ) {
    destination.withUnsafeMutableBytes { buffer in
      let bytes = buffer.bindMemory(to: UInt8.self)
      for spanIndex in 0..<spans.count {
        let span = spans[spanIndex]
        let destinationY = Double(span.y) + 0.5
        for x in span.x..<(span.x + span.length) {
          let destinationX = Double(x) + 0.5
          let sourcePoint = inverse.transform(RasterPoint(x: destinationX, y: destinationY))
          let tint = source.map {
            Self.sample($0, x: sourcePoint.x, y: sourcePoint.y, interpolation: interpolation)
          } ?? 0
          if overprints, tint == 0 { continue }
          let opacity: Double
          if let mask, let inverseMask {
            let maskPoint = inverseMask.transform(RasterPoint(x: destinationX, y: destinationY))
            opacity = Self.sample(mask, x: maskPoint.x, y: maskPoint.y, interpolation: maskInterpolation)
          } else {
            opacity = 1
          }
          let rendered = deviceRendering?.quantizeTint(tint, colorant: colorant, x: x, y: span.y)
            ?? tint
          let coverage = UInt16((Double(span.coverage) * opacity).rounded())
          let sourceByte = UInt16((rendered * 255).rounded())
          let offset = span.y * destinationWidth + x
          let old = UInt16(bytes[offset])
          bytes[offset] = UInt8((old * (255 - coverage) + sourceByte * coverage + 127) / 255)
        }
      }
    }
  }

  private static func sample(
    _ mask: RasterMask,
    x: Double,
    y: Double,
    interpolation: RasterInterpolation
  ) -> Double {
    switch interpolation {
    case .nearest:
      return Double(pixel(mask, x: Int(floor(x)), y: Int(floor(y)))) / 255
    case .linear:
      let sampleX = x - 0.5
      let sampleY = y - 0.5
      let x0 = Int(floor(sampleX))
      let y0 = Int(floor(sampleY))
      let fx = max(0, min(1, sampleX - Double(x0)))
      let fy = max(0, min(1, sampleY - Double(y0)))
      let top = Double(pixel(mask, x: x0, y: y0)) * (1 - fx)
        + Double(pixel(mask, x: x0 + 1, y: y0)) * fx
      let bottom = Double(pixel(mask, x: x0, y: y0 + 1)) * (1 - fx)
        + Double(pixel(mask, x: x0 + 1, y: y0 + 1)) * fx
      return (top * (1 - fy) + bottom * fy) / 255
    }
  }

  private static func pixel(_ mask: RasterMask, x: Int, y: Int) -> UInt8 {
    guard x >= 0, y >= 0, x < mask.width, y < mask.height else { return 0 }
    return mask.data[y * mask.bytesPerRow + x]
  }

  private borrowing func requireActive() throws(RasterError) {
    guard !finished else { throw .finishedCanvas }
  }
}
