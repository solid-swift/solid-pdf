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
  private var trapAnalysis: TrapAnalysis?

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
    trapAnalysis = nil
  }

  /// Enables or updates page trapping without discarding marks already recorded.
  public mutating func configureTrapping(
    _ program: RasterTrappingProgram
  ) throws(RasterError) {
    try requireActive()
    guard program.enabled else {
      trapAnalysis = nil
      return
    }
    if var analysis = trapAnalysis.take() {
      if analysis.program == program {
        trapAnalysis = analysis
        return
      }
      analysis.program = program
      trapAnalysis = analysis
    } else {
      let pixelCount = width.multipliedReportingOverflow(by: height)
      let continuousBytes = pixelCount.partialValue.multipliedReportingOverflow(by: colorants.count)
      let ownerBytes = pixelCount.partialValue.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
      let scratch = continuousBytes.partialValue.addingReportingOverflow(ownerBytes.partialValue)
      let all = scratch.partialValue.addingReportingOverflow(pixelCount.partialValue)
      guard !pixelCount.overflow, !continuousBytes.overflow, !ownerBytes.overflow,
        !scratch.overflow, !all.overflow,
        all.partialValue <= limits.maximumSurfaceBytes
      else { throw .limitExceeded }
      trapAnalysis = TrapAnalysis(
        program: program,
        continuousPlanes: colorants.map { _ in Data(repeating: 0, count: pixelCount.partialValue) },
        owners: [UInt32](repeating: 0, count: pixelCount.partialValue),
        kinds: Data(repeating: RasterTrappingMarkKind.vector.rawValue, count: pixelCount.partialValue),
        renderingPrograms: [:],
        nextOwner: 1,
        zoneIndexes: [Int32](repeating: -1, count: pixelCount.partialValue)
      )
    }
    try compileTrappingZones()
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
    if var analysis = trapAnalysis.take() {
      for index in analysis.continuousPlanes.indices {
        analysis.continuousPlanes[index].resetBytes(in: analysis.continuousPlanes[index].indices)
      }
      analysis.owners = [UInt32](repeating: 0, count: width * height)
      analysis.kinds.resetBytes(in: analysis.kinds.indices)
      analysis.renderingPrograms.removeAll(keepingCapacity: true)
      analysis.nextOwner = 1
      trapAnalysis = analysis
    }
  }

  /// Fills a path using subtractive colorant and overprint semantics.
  public mutating func fill(
    _ path: RasterPath,
    rule: RasterFillRule,
    paint: RasterColorantPaint,
    deviceRendering: RasterHalftoneProgram? = nil
  ) throws(RasterError) {
    try fill(
      path,
      rule: rule,
      paint: paint,
      deviceRendering: deviceRendering,
      markKind: .vector
    )
  }

  package mutating func fill(
    _ path: RasterPath,
    rule: RasterFillRule,
    paint: RasterColorantPaint,
    deviceRendering: RasterHalftoneProgram?,
    markKind: RasterTrappingMarkKind
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
    recordConstantMark(
      paint: paint,
      spans: spans.span,
      kind: markKind,
      deviceRendering: deviceRendering
    )
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
    try stroke(
      path,
      style: style,
      paint: paint,
      transform: transform,
      deviceRendering: deviceRendering,
      markKind: .vector
    )
  }

  package mutating func stroke(
    _ path: RasterPath,
    style: RasterStrokeStyle,
    paint: RasterColorantPaint,
    transform: RasterAffineTransform,
    deviceRendering: RasterHalftoneProgram?,
    markKind: RasterTrappingMarkKind
  ) throws(RasterError) {
    try fill(
      PathStroker.stroke(path, style: style, transform: transform),
      rule: .winding,
      paint: paint,
      deviceRendering: deviceRendering,
      markKind: markKind
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
    let markOwner = beginTrapMark(kind: .shading, deviceRendering: deviceRendering)
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
      recordGradientMark(triangle, spans: spans.span, owner: markOwner)
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
    recordImageMark(
      sources: sources,
      inverse: inverse,
      interpolation: interpolation,
      mask: mask,
      inverseMask: inverseMask,
      maskInterpolation: maskInterpolation,
      spans: spans.span,
      overprints: overprintsUnspecifiedColorants,
      deviceRendering: deviceRendering
    )
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
    applyTraps()
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

  private mutating func compileTrappingZones() throws(RasterError) {
    guard var analysis = trapAnalysis.take() else { return }
    analysis.zoneIndexes = [Int32](repeating: -1, count: width * height)
    for (zoneIndex, zone) in analysis.program.zones.enumerated() {
      guard zoneIndex <= Int(Int32.max) else { throw .limitExceeded }
      let spans = try rasterize(zone.path, rule: .winding)
      for span in spans where span.coverage > 0 {
        for x in span.x..<(span.x + span.length) {
          analysis.zoneIndexes[span.y * width + x] = Int32(zoneIndex)
        }
      }
    }
    trapAnalysis = analysis
  }

  private mutating func beginTrapMark(
    kind: RasterTrappingMarkKind,
    deviceRendering: RasterHalftoneProgram?
  ) -> UInt32? {
    guard var analysis = trapAnalysis.take() else { return nil }
    let owner = analysis.nextOwner
    analysis.nextOwner &+= 1
    if analysis.nextOwner == 0 { analysis.nextOwner = 1 }
    analysis.renderingPrograms[owner] = deviceRendering ?? .continuousTone
    trapAnalysis = analysis
    return owner
  }

  private mutating func recordConstantMark(
    paint: RasterColorantPaint,
    spans: borrowing Span<CoverageSpan>,
    kind: RasterTrappingMarkKind,
    deviceRendering: RasterHalftoneProgram?
  ) {
    guard let owner = beginTrapMark(kind: kind, deviceRendering: deviceRendering),
      var analysis = trapAnalysis.take()
    else { return }
    for spanIndex in 0..<spans.count {
      let span = spans[spanIndex]
      for x in span.x..<(span.x + span.length) {
        let offset = span.y * width + x
        for (planeIndex, name) in colorants.enumerated() {
          guard let tint = paint.tints[name] ?? (paint.overprintsUnspecifiedColorants ? nil : 0) else {
            continue
          }
          analysis.continuousPlanes[planeIndex][offset] = Self.blend(
            destination: analysis.continuousPlanes[planeIndex][offset],
            source: UInt8((min(1, max(0, tint)) * 255).rounded()),
            coverage: span.coverage
          )
        }
        analysis.owners[offset] = owner
        analysis.kinds[offset] = kind.rawValue
      }
    }
    trapAnalysis = analysis
  }

  private mutating func recordGradientMark(
    _ triangle: RasterColorantGradientTriangle,
    spans: borrowing Span<CoverageSpan>,
    owner: UInt32?
  ) {
    guard let owner, var analysis = trapAnalysis.take() else { return }
    let first = triangle.first.position
    let second = triangle.second.position
    let third = triangle.third.position
    let denominator = (second.y - third.y) * (first.x - third.x)
      + (third.x - second.x) * (first.y - third.y)
    guard denominator != 0, denominator.isFinite else {
      trapAnalysis = analysis
      return
    }
    let paints = [triangle.first.paint, triangle.second.paint, triangle.third.paint]
    for spanIndex in 0..<spans.count {
      let span = spans[spanIndex]
      let y = Double(span.y) + 0.5
      for x in span.x..<(span.x + span.length) {
        let centerX = Double(x) + 0.5
        let firstWeight = ((second.y - third.y) * (centerX - third.x)
          + (third.x - second.x) * (y - third.y)) / denominator
        let secondWeight = ((third.y - first.y) * (centerX - third.x)
          + (first.x - third.x) * (y - third.y)) / denominator
        let weights = [firstWeight, secondWeight, 1 - firstWeight - secondWeight]
        let offset = span.y * width + x
        for (planeIndex, name) in colorants.enumerated() {
          let values = paints.map { $0.tints[name] }
          if paints.allSatisfy(\.overprintsUnspecifiedColorants), values.allSatisfy({ $0 == nil }) {
            continue
          }
          let tint = zip(values, weights).reduce(0) { $0 + ($1.0 ?? 0) * $1.1 }
          analysis.continuousPlanes[planeIndex][offset] = Self.blend(
            destination: analysis.continuousPlanes[planeIndex][offset],
            source: UInt8((min(1, max(0, tint)) * 255).rounded()),
            coverage: span.coverage
          )
        }
        analysis.owners[offset] = owner
        analysis.kinds[offset] = RasterTrappingMarkKind.shading.rawValue
      }
    }
    trapAnalysis = analysis
  }

  private mutating func recordImageMark(
    sources: [String: RasterMask],
    inverse: RasterAffineTransform,
    interpolation: RasterInterpolation,
    mask: RasterMask?,
    inverseMask: RasterAffineTransform?,
    maskInterpolation: RasterInterpolation,
    spans: borrowing Span<CoverageSpan>,
    overprints: Bool,
    deviceRendering: RasterHalftoneProgram?
  ) {
    guard let owner = beginTrapMark(kind: .image, deviceRendering: deviceRendering),
      var analysis = trapAnalysis.take()
    else { return }
    for spanIndex in 0..<spans.count {
      let span = spans[spanIndex]
      for x in span.x..<(span.x + span.length) {
        let point = inverse.transform(RasterPoint(x: Double(x) + 0.5, y: Double(span.y) + 0.5))
        let opacity: Double
        if let mask, let inverseMask {
          let maskPoint = inverseMask.transform(RasterPoint(x: Double(x) + 0.5, y: Double(span.y) + 0.5))
          opacity = Self.sample(mask, x: maskPoint.x, y: maskPoint.y, interpolation: maskInterpolation)
        } else {
          opacity = 1
        }
        let coverage = UInt8((Double(span.coverage) * opacity).rounded())
        let offset = span.y * width + x
        for (planeIndex, name) in colorants.enumerated() {
          guard let source = sources[name] else {
            if !overprints {
              analysis.continuousPlanes[planeIndex][offset] = Self.blend(
                destination: analysis.continuousPlanes[planeIndex][offset],
                source: 0,
                coverage: coverage
              )
            }
            continue
          }
          let tint = Self.sample(source, x: point.x, y: point.y, interpolation: interpolation)
          analysis.continuousPlanes[planeIndex][offset] = Self.blend(
            destination: analysis.continuousPlanes[planeIndex][offset],
            source: UInt8((tint * 255).rounded()),
            coverage: coverage
          )
        }
        if coverage > 0 {
          analysis.owners[offset] = owner
          analysis.kinds[offset] = RasterTrappingMarkKind.image.rawValue
        }
      }
    }
    trapAnalysis = analysis
  }

  private mutating func applyTraps() {
    guard let analysis = trapAnalysis, analysis.program.enabled, !analysis.program.zones.isEmpty else { return }
    let directions = [(1, 0), (0, 1)]
    for y in 0..<height {
      for x in 0..<width {
        let firstOffset = y * width + x
        let firstOwner = analysis.owners[firstOffset]
        guard firstOwner != 0 else { continue }
        for (dx, dy) in directions {
          let adjacentX = x + dx
          let adjacentY = y + dy
          guard adjacentX < width, adjacentY < height else { continue }
          let secondOffset = adjacentY * width + adjacentX
          let secondOwner = analysis.owners[secondOffset]
          guard secondOwner != 0 else { continue }
          let firstKind = RasterTrappingMarkKind(rawValue: analysis.kinds[firstOffset]) ?? .vector
          let secondKind = RasterTrappingMarkKind(rawValue: analysis.kinds[secondOffset]) ?? .vector
          let internalImageBoundary = firstOwner == secondOwner
            && firstKind == .image && secondKind == .image
            && analysis.program.trapsInsideImages
          guard firstOwner != secondOwner || internalImageBoundary else { continue }
          if firstKind == .image || secondKind == .image {
            if internalImageBoundary,
              x % analysis.program.imageAnalysisStride != 0,
              y % analysis.program.imageAnalysisStride != 0
            { continue }
            if firstKind == .image, secondKind == .image, !analysis.program.trapsInsideImages { continue }
            if firstKind != secondKind, !analysis.program.trapsImagesToObjects { continue }
          }
          let zoneIndex = max(analysis.zoneIndexes[firstOffset], analysis.zoneIndexes[secondOffset])
          guard zoneIndex >= 0, Int(zoneIndex) < analysis.program.zones.count else { continue }
          applyTrapBoundary(
            firstOffset: firstOffset,
            secondOffset: secondOffset,
            firstPoint: (x, y),
            secondPoint: (adjacentX, adjacentY),
            zoneIndex: Int(zoneIndex),
            analysis: analysis
          )
        }
      }
    }
  }

  private mutating func applyTrapBoundary(
    firstOffset: Int,
    secondOffset: Int,
    firstPoint: (Int, Int),
    secondPoint: (Int, Int),
    zoneIndex: Int,
    analysis: TrapAnalysis
  ) {
    let zone = analysis.program.zones[zoneIndex]
    let first = analysis.continuousPlanes.map { Double($0[firstOffset]) / 255 }
    let second = analysis.continuousPlanes.map { Double($0[secondOffset]) / 255 }
    var positive = false
    var negative = false
    for index in colorants.indices {
      let name = colorants[index]
      let behavior = analysis.program.colorantBehaviors[name] ?? .normal
      guard behavior != .transparent, behavior != .opaqueIgnore else { continue }
      let delta = first[index] - second[index]
      let stepLimit = zone.colorantStepLimits[name] ?? zone.stepLimit
      let threshold = max(0.05, stepLimit * max(first[index], second[index]))
      if delta > threshold { positive = true }
      if delta < -threshold { negative = true }
    }
    guard positive, negative else { return }
    func density(_ tints: [Double]) -> Double {
      zip(colorants, tints).reduce(0) { result, pair in
        let behavior = analysis.program.colorantBehaviors[pair.0] ?? .normal
        guard behavior != .transparent, behavior != .opaqueIgnore else { return result }
        return result + pair.1 * (analysis.program.neutralDensities[pair.0] ?? 1)
      }
    }
    let firstDensity = density(first)
    let secondDensity = density(second)
    let firstIsLighter = firstDensity <= secondDensity
    let lighter = firstIsLighter ? first : second
    let lighterOwner = firstIsLighter ? analysis.owners[firstOffset] : analysis.owners[secondOffset]
    let lighterPoint = firstIsLighter ? firstPoint : secondPoint
    let darker = firstIsLighter ? second : first
    let darkerOwner = firstIsLighter ? analysis.owners[secondOffset] : analysis.owners[firstOffset]
    let darkerPoint = firstIsLighter ? secondPoint : firstPoint
    var radius = max(1, Int(zone.width.rounded(.up)))
    let blackIndex = colorants.firstIndex(where: { $0 == "Black" || $0 == "Gray" })
    let hasBlackBoundary = blackIndex.map {
      max(first[$0], second[$0]) >= analysis.program.blackDensityLimit
    } ?? false
    if hasBlackBoundary {
      radius = max(radius, Int((zone.width * analysis.program.blackWidth).rounded(.up)))
    }

    let firstKind = RasterTrappingMarkKind(rawValue: analysis.kinds[firstOffset]) ?? .vector
    let secondKind = RasterTrappingMarkKind(rawValue: analysis.kinds[secondOffset]) ?? .vector
    if firstKind == .image, secondKind != .image {
      applyImageBoundary(
        image: first,
        imageOwner: analysis.owners[firstOffset],
        imagePoint: firstPoint,
        object: second,
        objectOwner: analysis.owners[secondOffset],
        objectPoint: secondPoint,
        radius: radius,
        zoneIndex: zoneIndex,
        analysis: analysis
      )
    } else if secondKind == .image, firstKind != .image {
      applyImageBoundary(
        image: second,
        imageOwner: analysis.owners[secondOffset],
        imagePoint: secondPoint,
        object: first,
        objectOwner: analysis.owners[firstOffset],
        objectPoint: firstPoint,
        radius: radius,
        zoneIndex: zoneIndex,
        analysis: analysis
      )
    } else {
      applyTrapInk(
        lighter,
        sourceOwner: lighterOwner,
        toOwner: darkerOwner,
        around: darkerPoint,
        radius: radius,
        zoneIndex: zoneIndex,
        analysis: analysis
      )
      let maximumDensity = max(firstDensity, secondDensity)
      let densityRatio = maximumDensity > 0 ? min(firstDensity, secondDensity) / maximumDensity : 1
      let centeredFraction = min(1, densityRatio / max(0.000_001, analysis.program.slidingLimit))
      let reverseRadius = Int((Double(radius) * centeredFraction * 0.5).rounded(.down))
      if reverseRadius > 0 {
        applyTrapInk(
          darker,
          sourceOwner: darkerOwner,
          toOwner: lighterOwner,
          around: lighterPoint,
          radius: reverseRadius,
          zoneIndex: zoneIndex,
          analysis: analysis,
          onlyBlack: hasBlackBoundary && isRichBlack(darker, blackIndex: blackIndex, analysis: analysis)
        )
      }
    }
  }

  private mutating func applyImageBoundary(
    image: [Double],
    imageOwner: UInt32,
    imagePoint: (Int, Int),
    object: [Double],
    objectOwner: UInt32,
    objectPoint: (Int, Int),
    radius: Int,
    zoneIndex: Int,
    analysis: TrapAnalysis
  ) {
    switch analysis.program.imagePlacement {
    case .normal:
      let imageDensity = trapDensity(image, analysis: analysis)
      let objectDensity = trapDensity(object, analysis: analysis)
      if imageDensity <= objectDensity {
        applyTrapInk(
          image,
          sourceOwner: imageOwner,
          toOwner: objectOwner,
          around: objectPoint,
          radius: radius,
          zoneIndex: zoneIndex,
          analysis: analysis
        )
      } else {
        applyTrapInk(
          object,
          sourceOwner: objectOwner,
          toOwner: imageOwner,
          around: imagePoint,
          radius: radius,
          zoneIndex: zoneIndex,
          analysis: analysis
        )
      }
    case .spread:
      applyTrapInk(
        image,
        sourceOwner: imageOwner,
        toOwner: objectOwner,
        around: objectPoint,
        radius: radius,
        zoneIndex: zoneIndex,
        analysis: analysis
      )
    case .choke:
      applyTrapInk(
        object,
        sourceOwner: objectOwner,
        toOwner: imageOwner,
        around: imagePoint,
        radius: radius,
        zoneIndex: zoneIndex,
        analysis: analysis
      )
    case .center:
      let centeredRadius = max(1, Int((Double(radius) * 0.5).rounded(.up)))
      applyTrapInk(
        image,
        sourceOwner: imageOwner,
        toOwner: objectOwner,
        around: objectPoint,
        radius: centeredRadius,
        zoneIndex: zoneIndex,
        analysis: analysis
      )
      applyTrapInk(
        object,
        sourceOwner: objectOwner,
        toOwner: imageOwner,
        around: imagePoint,
        radius: centeredRadius,
        zoneIndex: zoneIndex,
        analysis: analysis
      )
    }
  }

  private mutating func applyTrapInk(
    _ source: [Double],
    sourceOwner: UInt32,
    toOwner targetOwner: UInt32,
    around point: (Int, Int),
    radius: Int,
    zoneIndex: Int,
    analysis: TrapAnalysis,
    onlyBlack: Bool = false
  ) {
    let zone = analysis.program.zones[zoneIndex]
    let rendering = analysis.renderingPrograms[sourceOwner] ?? .continuousTone
    for targetY in max(0, point.1 - radius)...min(height - 1, point.1 + radius) {
      for targetX in max(0, point.0 - radius)...min(width - 1, point.0 + radius) {
        let targetOffset = targetY * width + targetX
        guard analysis.owners[targetOffset] == targetOwner,
          analysis.zoneIndexes[targetOffset] == Int32(zoneIndex)
        else { continue }
        for planeIndex in colorants.indices {
          let name = colorants[planeIndex]
          let behavior = analysis.program.colorantBehaviors[name] ?? .normal
          guard behavior != .transparent, behavior != .opaqueIgnore,
            !onlyBlack || name == "Black" || name == "Gray"
          else { continue }
          let scaling = zone.colorantColorScales[name] ?? zone.colorScaling
          let requested = min(1, source[planeIndex] * scaling)
          let realized = rendering.quantizeTint(requested, colorant: name, x: targetX, y: targetY)
          let byte = UInt8((realized * 255).rounded())
          if byte > planes[planeIndex][targetOffset] {
            planes[planeIndex][targetOffset] = byte
          }
        }
      }
    }
  }

  private func trapDensity(_ tints: [Double], analysis: TrapAnalysis) -> Double {
    zip(colorants, tints).reduce(0) { result, pair in
      let behavior = analysis.program.colorantBehaviors[pair.0] ?? .normal
      guard behavior != .transparent, behavior != .opaqueIgnore else { return result }
      return result + pair.1 * (analysis.program.neutralDensities[pair.0] ?? 1)
    }
  }

  private func isRichBlack(
    _ tints: [Double],
    blackIndex: Int?,
    analysis: TrapAnalysis
  ) -> Bool {
    guard let blackIndex, tints[blackIndex] >= analysis.program.blackDensityLimit else { return false }
    let support = tints.indices.filter { $0 != blackIndex }.reduce(0) { $0 + tints[$1] }
    return support > analysis.program.blackColorLimit
  }

  private static func blend(destination: UInt8, source: UInt8, coverage: UInt8) -> UInt8 {
    let destination = UInt16(destination)
    let source = UInt16(source)
    let coverage = UInt16(coverage)
    return UInt8((destination * (255 - coverage) + source * coverage + 127) / 255)
  }

  private borrowing func requireActive() throws(RasterError) {
    guard !finished else { throw .finishedCanvas }
  }
}

private struct TrapAnalysis {
  var program: RasterTrappingProgram
  var continuousPlanes: [Data]
  var owners: [UInt32]
  var kinds: Data
  var renderingPrograms: [UInt32: RasterHalftoneProgram]
  var nextOwner: UInt32
  var zoneIndexes: [Int32]
}
