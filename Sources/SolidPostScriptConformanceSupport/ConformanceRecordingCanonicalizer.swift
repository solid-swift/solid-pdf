import Foundation
import SolidColor
import SolidPostScript

package enum ConformanceRecordingCanonicalizer {
  package static func digest(_ recording: GraphicsRecording) -> String {
    var writer = Writer()
    writer.token("recording-v3")
    writer.integer(recording.pages.count)
    for page in recording.pages {
      writer.deviceSnapshot(page.device)
      writer.transmission(page.transmission)
      writer.integer(page.copyOrdinal)
      writer.coordinateMapping(page.coordinateMapping)
      writer.trapping(page.trapping)
      writer.effects(page.effects, depth: 0)
    }
    return ConformanceDigest.sha256(writer.data)
  }
}

private struct Writer {
  var data = Data()
  private var resourceIdentifiers: [GraphicsResourceIdentifier: Int] = [:]
  private var deviceIdentifiers: [GraphicsDeviceIdentifier: Int] = [:]
  private var outputDeviceIdentifiers: [GraphicsOutputDeviceIdentifier: Int] = [:]

  mutating func token(_ value: String) {
    data.append(Data(value.utf8).map { String(format: "%02x", $0) }.joined().data(using: .ascii)!)
    data.append(0x0A)
  }

  mutating func integer<T: BinaryInteger>(_ value: T) { token(String(value)) }
  mutating func boolean(_ value: Bool) { token(value ? "1" : "0") }
  mutating func double(_ value: Double) { token(String(value.bitPattern, radix: 16)) }
  mutating func float(_ value: Float) { token(String(value.bitPattern, radix: 16)) }

  mutating func binary(_ value: Data?) {
    guard let value else {
      token("nil")
      return
    }
    integer(value.count)
    token(ConformanceDigest.sha256(value))
  }

  mutating func resource(_ value: GraphicsResourceIdentifier) {
    guard !value.isAnonymous else {
      token("anonymous")
      return
    }
    if let ordinal = resourceIdentifiers[value] {
      integer(ordinal)
    } else {
      let ordinal = resourceIdentifiers.count + 1
      resourceIdentifiers[value] = ordinal
      integer(ordinal)
    }
    if let key = value.stableKey {
      token(key.namespace)
      binary(key.value)
    } else {
      token("nil")
    }
  }

  mutating func point(_ value: GraphicsPoint) {
    double(value.x)
    double(value.y)
  }

  mutating func rectangle(_ value: GraphicsRect?) {
    guard let value else {
      token("nil")
      return
    }
    double(value.x)
    double(value.y)
    double(value.width)
    double(value.height)
  }

  mutating func matrix(_ value: GraphicsMatrix) {
    for component in [value.a, value.b, value.c, value.d, value.tx, value.ty] { double(component) }
  }

  mutating func path(_ value: GraphicsPath) {
    integer(value.elements.count)
    for element in value.elements {
      switch element {
      case .move(let destination):
        token("move")
        point(destination)
      case .line(let destination):
        token("line")
        point(destination)
      case .curve(let first, let second, let end):
        token("curve")
        point(first)
        point(second)
        point(end)
      case .close:
        token("close")
      }
    }
  }

  mutating func colorSpace(_ value: GraphicsColorSpaceDescription) {
    switch value {
    case .deviceGray: token("DeviceGray")
    case .deviceRGB: token("DeviceRGB")
    case .deviceCMYK: token("DeviceCMYK")
    case .cieBasedA(let whitePoint):
      token("CIEBasedA")
      xyz(whitePoint)
    case .cieBasedABC(let whitePoint):
      token("CIEBasedABC")
      xyz(whitePoint)
    case .cieBasedDEF(let whitePoint):
      token("CIEBasedDEF")
      xyz(whitePoint)
    case .cieBasedDEFG(let whitePoint):
      token("CIEBasedDEFG")
      xyz(whitePoint)
    case .indexed(let base, let maximumIndex):
      token("Indexed")
      colorSpace(base)
      integer(maximumIndex)
    case .separation(let name, let alternative):
      token("Separation")
      token(name)
      colorSpace(alternative)
    case .deviceN(let names, let alternative):
      token("DeviceN")
      integer(names.count)
      names.forEach { token($0) }
      colorSpace(alternative)
    case .pattern(let underlying):
      token("Pattern")
      if let underlying { colorSpace(underlying) } else { token("nil") }
    }
  }

  mutating func paint(_ value: GraphicsPaint, depth: Int) {
    switch value {
    case .deviceGray(let gray):
      token("gray")
      double(gray)
    case .deviceRGB(let red, let green, let blue):
      token("rgb")
      [red, green, blue].forEach { double($0) }
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      token("cmyk")
      [cyan, magenta, yellow, black].forEach { double($0) }
    case .color(let color):
      token("color")
      colorValue(color)
    case .pattern(let pattern):
      token("pattern")
      patternPaint(pattern, depth: depth)
    }
  }

  mutating func colorValue(_ value: GraphicsColorValue) {
    switch value {
    case .deviceGray(let gray):
      token("gray")
      double(gray)
    case .deviceRGB(let value):
      token("rgb")
      [value.red, value.green, value.blue].forEach { double($0) }
    case .deviceCMYK(let value):
      token("cmyk")
      [value.cyan, value.magenta, value.yellow, value.black].forEach { double($0) }
    case .cie(let space, let source, let value, let device):
      token("cie")
      colorSpace(space)
      doubles(source)
      xyz(value)
      if let device { colorValue(device) } else { token("nil") }
    case .named(let space, let colorants, let tints, let alternative):
      token("named")
      colorSpace(space)
      integer(colorants.count)
      colorants.forEach { token($0) }
      doubles(tints)
      colorValue(alternative)
    case .directColorants(let space, let colorants, let tints):
      token("direct")
      colorSpace(space)
      integer(colorants.count)
      colorants.forEach { token($0) }
      doubles(tints)
    }
  }

  mutating func xyz(_ value: ColorXYZ) {
    [value.x, value.y, value.z].forEach { double($0) }
  }

  mutating func doubles(_ values: [Double]) {
    integer(values.count)
    values.forEach { double($0) }
  }

  mutating func floats(_ values: [Float]?) {
    guard let values else {
      token("nil")
      return
    }
    integer(values.count)
    let byteCount = values.count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.size)
    guard !byteCount.overflow else {
      token("overflow")
      return
    }
    var bytes = Data(capacity: byteCount.partialValue)
    for value in values {
      var bits = value.bitPattern.bigEndian
      withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
    }
    binary(bytes)
  }

  mutating func state(_ value: GraphicsStateSnapshot, depth: Int) {
    matrix(value.matrix)
    path(value.path)
    rectangle(value.clip.imageableBounds)
    integer(value.clip.constraints.count)
    for constraint in value.clip.constraints {
      path(constraint.path)
      token(constraint.rule == .winding ? "winding" : "evenOdd")
    }
    paint(value.paint, depth: depth)
    colorSpace(value.colorSpace)
    colorRealization(value.colorRealization)
    doubles(value.colorComponents)
    boolean(value.overprint)
    double(value.lineWidth)
    integer(value.lineCap.rawValue)
    integer(value.lineJoin.rawValue)
    double(value.miterLimit)
    doubles(value.dash.pattern)
    double(value.dash.phase)
    double(value.flatness)
    boolean(value.strokeAdjustment)
    double(value.smoothness)
    rectangle(value.pathBoundingBox)
    deviceSnapshot(value.device)
    rendering(value.deviceRendering)
    font(value.font)
  }

  mutating func colorRealization(_ value: GraphicsColorSpaceRealization?) {
    guard let value else {
      token("nil")
      return
    }
    integer(value.componentRanges.count)
    for range in value.componentRanges {
      double(range.lowerBound)
      double(range.upperBound)
    }
    binary(value.indexedLookup)
    if let alternative = value.alternativeSpace { colorSpace(alternative) } else { token("nil") }
    if let transform = value.sampledTransform {
      integer(transform.size.count)
      transform.size.forEach { integer($0) }
      integer(transform.outputComponentCount)
      binary(transform.samples)
    } else {
      token("nil")
    }
  }

  mutating func device(_ value: GraphicsDeviceDescriptor) {
    rectangle(value.mediaBounds)
    rectangle(value.imageableBounds)
    double(value.horizontalResolution)
    double(value.verticalResolution)
    matrix(value.defaultMatrix)
    double(value.defaultFlatness)
    boolean(value.defaultStrokeAdjustment)
    double(value.minimumSmoothness)
    double(value.maximumSmoothness)
    double(value.defaultSmoothness)
  }

  mutating func deviceSnapshot(_ value: GraphicsDeviceSnapshot) {
    deviceIdentity(value.identifier)
    outputDeviceIdentity(value.outputDeviceIdentifier)
    token(String(describing: value.kind))
    device(value.descriptor)
    integer(value.pageNumber)
    integer(value.numberOfCopies ?? -1)
    boolean(value.usesCIEColor)
    token(String(describing: value.mediaSelection))
    token(String(describing: value.placement))
    token(String(describing: value.delivery))
    trapping(value.trapping)
  }

  mutating func deviceIdentity(_ value: GraphicsDeviceIdentifier) {
    if let ordinal = deviceIdentifiers[value] {
      integer(ordinal)
    } else {
      let ordinal = deviceIdentifiers.count + 1
      deviceIdentifiers[value] = ordinal
      integer(ordinal)
    }
  }

  mutating func outputDeviceIdentity(_ value: GraphicsOutputDeviceIdentifier) {
    if let ordinal = outputDeviceIdentifiers[value] {
      integer(ordinal)
    } else {
      let ordinal = outputDeviceIdentifiers.count + 1
      outputDeviceIdentifiers[value] = ordinal
      integer(ordinal)
    }
  }

  mutating func transmission(_ value: GraphicsPageTransmission) {
    token(String(describing: value.trigger))
    integer(value.logicalOrdinal)
    integer(value.copies)
    token(String(describing: value.mediaSelection))
    token(String(describing: value.placement))
    token(String(describing: value.delivery))
  }

  mutating func coordinateMapping(_ value: GraphicsPageCoordinateMapping) {
    matrix(value.pageToDevice)
    if let inverse = value.deviceToPage { matrix(inverse) } else { token("nil") }
    rectangle(value.mediaBounds)
    rectangle(value.imageableBounds)
  }

  mutating func rendering(_ value: GraphicsDeviceRenderingSnapshot) {
    componentFunction(value.transferFunctions.red)
    componentFunction(value.transferFunctions.green)
    componentFunction(value.transferFunctions.blue)
    componentFunction(value.transferFunctions.gray)
    componentFunction(value.blackGeneration)
    componentFunction(value.undercolorRemoval)
    halftone(value.halftone)
  }

  mutating func trapping(_ value: GraphicsTrappingSnapshot) {
    boolean(value.enabled)
    integer(value.details.type)
    integer(value.details.trappingOrder.count)
    value.details.trappingOrder.forEach { token($0) }
    integer(value.details.colorantDetails.count)
    for key in value.details.colorantDetails.keys.sorted() {
      let detail = value.details.colorantDetails[key]!
      token(key)
      token(detail.colorantName)
      token(detail.colorantType.rawValue)
      double(detail.neutralDensity)
    }
    trappingParameters(value.parameters)
    integer(value.zones.count)
    for zone in value.zones {
      path(zone.path)
      trappingParameters(zone.parameters)
      integer(zone.sequence)
    }
  }

  mutating func trappingParameters(_ value: GraphicsTrappingParameters) {
    token(value.trapSetName ?? "nil")
    boolean(value.enabled)
    for component in [
      value.stepLimit,
      value.trapWidth,
      value.trapColorScaling,
      value.blackDensityLimit,
      value.blackColorLimit,
      value.blackWidth,
      value.slidingTrapLimit,
      value.imageResolution,
    ] { double(component) }
    boolean(value.imageToObjectTrapping)
    boolean(value.imageInternalTrapping)
    token(value.imageTrapPlacement.rawValue)
    integer(value.colorantZoneDetails.count)
    for key in value.colorantZoneDetails.keys.sorted() {
      let detail = value.colorantZoneDetails[key]!
      token(key)
      if let stepLimit = detail.stepLimit { double(stepLimit) } else { token("nil") }
      if let trapColorScaling = detail.trapColorScaling { double(trapColorScaling) } else { token("nil") }
    }
  }

  mutating func componentFunction(_ value: GraphicsComponentFunction?) {
    guard let value else {
      token("nil")
      return
    }
    doubles(value.samples)
  }

  mutating func halftone(_ value: GraphicsHalftone) {
    switch value {
    case .continuous:
      token("continuous")
    case .spot(let screen):
      token("spot")
      [screen.frequency, screen.angle, screen.actualFrequency, screen.actualAngle].forEach { double($0) }
      integer(screen.width)
      integer(screen.height)
      integer(screen.thresholds.count)
      screen.thresholds.forEach { integer($0) }
      componentFunction(screen.transferFunction)
    case .threshold(let screen):
      token("threshold")
      integer(screen.width)
      integer(screen.height)
      integer(screen.bitsPerSample)
      integer(screen.secondaryWidth ?? 0)
      integer(screen.secondaryHeight ?? 0)
      boolean(screen.usesAngledSquares)
      integer(screen.thresholds.count)
      screen.thresholds.forEach { integer($0) }
      componentFunction(screen.transferFunction)
    case .colorants(let screens):
      token("colorants")
      integer(screens.count)
      for key in screens.keys.sorted() {
        token(key)
        halftone(screens[key]!)
      }
    }
  }

  mutating func font(_ value: GraphicsFontDescription) {
    token(value.identifier.value)
    token(value.resourceName ?? "nil")
    token(value.postScriptName ?? "nil")
    matrix(value.matrix)
    integer(value.writingMode)
    token(String(describing: value.outlineAccess))
    token(String(describing: value.technology))
    integer(value.fontType ?? -1)
    integer(value.paintType)
    double(value.strokeWidth)
    resource(value.resourceIdentifier)
    if let substitution = value.substitution {
      token(substitution.requestedName)
      token(substitution.resolvedName ?? "nil")
      token(substitution.providerIdentifier)
      boolean(substitution.isCIDCompatible)
    } else {
      token("nil")
    }
    if let asset = value.asset {
      token(String(describing: asset.format))
      integer(asset.faceIndex)
      binary(asset.data)
    } else {
      token("nil")
    }
  }

  mutating func effects(_ values: [GraphicsEffect], depth: Int) {
    guard depth <= 32 else {
      token("depth-limit")
      return
    }
    integer(values.count)
    values.forEach { effect($0, depth: depth) }
  }

  mutating func effect(_ value: GraphicsEffect, depth: Int) {
    switch value {
    case .fill(let pathValue, let rule, let stateValue):
      token("fill")
      path(pathValue)
      token(rule == .winding ? "winding" : "evenOdd")
      state(stateValue, depth: depth)
    case .stroke(let pathValue, let stateValue):
      token("stroke")
      path(pathValue)
      state(stateValue, depth: depth)
    case .userPathFill(let pathValue, let rule, let stateValue):
      token("userPathFill")
      path(pathValue)
      token(rule == .winding ? "winding" : "evenOdd")
      state(stateValue, depth: depth)
    case .userPathStroke(let outline, let stateValue):
      token("userPathStroke")
      path(outline)
      state(stateValue, depth: depth)
    case .erase(let stateValue):
      token("erase")
      state(stateValue, depth: depth)
    case .fillRectangles(let paths, let stateValue):
      token("fillRectangles")
      integer(paths.count)
      paths.forEach { path($0) }
      state(stateValue, depth: depth)
    case .strokeRectangles(let paths, let optionalMatrix, let stateValue):
      token("strokeRectangles")
      integer(paths.count)
      paths.forEach { path($0) }
      if let optionalMatrix { matrix(optionalMatrix) } else { token("nil") }
      state(stateValue, depth: depth)
    case .image(let image, let stateValue):
      token("image")
      sampledImage(image)
      state(stateValue, depth: depth)
    case .shading(let shading, let stateValue):
      token("shading")
      shadingValue(shading, depth: depth)
      state(stateValue, depth: depth)
    case .form(let form, let stateValue):
      token("form")
      resource(form.resourceIdentifier)
      rectangle(form.bounds)
      matrix(form.matrix)
      resource(form.displayList.resourceIdentifier)
      effects(form.displayList.effects, depth: depth + 1)
      state(stateValue, depth: depth)
    case .text(let run, let stateValue):
      token("text")
      glyphRun(run, depth: depth)
      state(stateValue, depth: depth)
    }
  }

  mutating func sampledImage(_ value: GraphicsImage) {
    resource(value.descriptor.resourceIdentifier)
    integer(value.descriptor.sourceType.rawValue)
    integer(value.descriptor.width)
    integer(value.descriptor.height)
    integer(value.descriptor.sourceBitsPerComponent)
    integer(value.descriptor.sourceComponentCount)
    doubles(value.descriptor.decode)
    colorRealization(value.descriptor.colorRealization)
    matrix(value.descriptor.imageToDevice)
    boolean(value.descriptor.interpolate)
    switch value.descriptor.kind {
    case .color(let colorSpace):
      token("color")
      integer(colorSpace.rawValue)
    case .mask(let maskPaint):
      token("stencil")
      paint(maskPaint, depth: 0)
    }
    if let sourceColorSpace = value.descriptor.sourceColorSpace {
      colorSpace(sourceColorSpace)
    } else {
      token("nil")
    }
    imageMaskDescriptor(value.descriptor.mask)
    floats(value.components)
    floats(value.sourceComponents)
    binary(value.rawSamples)
    if let mask = value.mask {
      token("mask")
      imageMaskDescriptor(mask.descriptor)
      floats(mask.opacities)
    } else {
      token("nil")
    }
  }

  mutating func imageMaskDescriptor(_ value: GraphicsImageMaskDescriptor?) {
    guard let value else {
      token("nil")
      return
    }
    switch value {
    case .explicit(let width, let height, let maskToDevice, let interpolate):
      token("explicit")
      integer(width)
      integer(height)
      matrix(maskToDevice)
      boolean(interpolate)
    case .colorKey(let ranges):
      token("colorKey")
      integer(ranges.count)
      for range in ranges {
        integer(range.lowerBound)
        integer(range.upperBound)
      }
    }
  }

  mutating func patternPaint(_ value: GraphicsPatternPaint, depth: Int) {
    switch value {
    case .empty:
      token("empty")
    case .tiling(let pattern, let underlying):
      token("tiling")
      resource(pattern.resourceIdentifier)
      integer(pattern.paintType)
      integer(pattern.tilingType)
      rectangle(pattern.bounds)
      double(pattern.xStep)
      double(pattern.yStep)
      matrix(pattern.matrix)
      if let underlying { paint(underlying, depth: depth + 1) } else { token("nil") }
      resource(pattern.displayList.resourceIdentifier)
      effects(pattern.displayList.effects, depth: depth + 1)
    case .shading(let shading):
      token("shadingPattern")
      shadingValue(shading, depth: depth + 1)
    }
  }

  mutating func shadingValue(_ value: GraphicsShading, depth: Int) {
    resource(value.resourceIdentifier)
    integer(value.type)
    colorSpace(value.colorSpace)
    colorRealization(value.colorRealization)
    if let background = value.background { paint(background, depth: depth) } else { token("nil") }
    rectangle(value.bounds)
    if let clipPath = value.clipPath { path(clipPath) } else { token("nil") }
    boolean(value.antialias)
    shadingGeometry(value.geometry)
    integer(value.sourcePatches.count)
    for patch in value.sourcePatches {
      integer(patch.type)
      integer(patch.continuationFlag)
      integer(patch.controlPoints.count)
      patch.controlPoints.forEach { point($0) }
      integer(patch.cornerComponents.count)
      for components in patch.cornerComponents {
        integer(components.count)
        components.forEach { double($0) }
      }
    }
    integer(value.mesh.triangles.count)
    for triangle in value.mesh.triangles {
      for vertex in [triangle.first, triangle.second, triangle.third] {
        point(vertex.position)
        paint(vertex.paint, depth: depth)
      }
    }
  }

  mutating func shadingGeometry(_ value: GraphicsShadingGeometry) {
    switch value {
    case .function(let domain, let transform, let functions):
      token("function")
      rectangle(domain)
      matrix(transform)
      integer(functions.count)
      functions.forEach { token(String(describing: $0)) }
    case .axial(let start, let end, let domainStart, let domainEnd, let extendStart, let extendEnd, let functions):
      token("axial")
      point(start)
      point(end)
      double(domainStart)
      double(domainEnd)
      boolean(extendStart)
      boolean(extendEnd)
      integer(functions.count)
      functions.forEach { token(String(describing: $0)) }
    case .radial(
      let startCenter, let startRadius, let endCenter, let endRadius,
      let domainStart, let domainEnd, let extendStart, let extendEnd, let functions
    ):
      token("radial")
      point(startCenter)
      double(startRadius)
      point(endCenter)
      double(endRadius)
      double(domainStart)
      double(domainEnd)
      boolean(extendStart)
      boolean(extendEnd)
      integer(functions.count)
      functions.forEach { token(String(describing: $0)) }
    case .triangles(let type, let vertexCount):
      token("triangles")
      integer(type)
      integer(vertexCount)
    case .patches(let type, let patchCount):
      token("patches")
      integer(type)
      integer(patchCount)
    }
  }

  mutating func glyphRun(_ value: GraphicsGlyphRun, depth: Int) {
    integer(value.renderingMode.rawValue)
    if let style = value.style {
      textPaint(style.fill, depth: depth)
      textPaint(style.stroke, depth: depth)
    } else {
      token("nil")
    }
    font(value.rootFont)
    binary(value.sourceBytes)
    integer(value.glyphs.count)
    for placement in value.glyphs {
      if let fontValue = placement.font { font(fontValue) } else { token("nil") }
      glyphSelector(placement.glyph.selector)
      resource(placement.glyph.resourceIdentifier)
      integer(placement.glyph.resolvedGlyphIndex ?? UInt32.max)
      point(placement.glyph.metrics.horizontalAdvance)
      if let vertical = placement.glyph.metrics.verticalAdvance { point(vertical) } else { token("nil") }
      if let origin = placement.glyph.metrics.verticalOrigin { point(origin) } else { token("nil") }
      rectangle(placement.glyph.metrics.bounds)
      point(placement.origin)
      matrix(placement.transform)
      point(placement.advance)
      binary(placement.sourceBytes)
      if let range = placement.sourceRange {
        integer(range.lowerBound)
        integer(range.upperBound)
      } else {
        token("nil")
      }
      token(placement.unicodeProvenance.map(String.init(describing:)) ?? "nil")
      if let scalars = placement.unicodeScalars {
        integer(scalars.count)
        scalars.forEach { integer($0.value) }
      } else {
        token("nil")
      }
      switch placement.glyph.program {
      case .outline(let pathValue):
        token("outline")
        path(pathValue)
      case .bitmap(let bitmap):
        token("bitmap")
        integer(bitmap.width)
        integer(bitmap.height)
        integer(bitmap.bytesPerRow)
        integer(bitmap.originX)
        integer(bitmap.originY)
        binary(bitmap.coverage)
      case .displayList(let displayList):
        token("displayList")
        resource(displayList.resourceIdentifier)
        effects(displayList.effects, depth: depth + 1)
      case .empty: token("empty")
      case .missing: token("missing")
      }
    }
  }

  mutating func textPaint(_ value: GraphicsTextPaint, depth: Int) {
    paint(value.paint, depth: depth)
    colorSpace(value.colorSpace)
    colorRealization(value.colorRealization)
    doubles(value.components)
    boolean(value.overprint)
  }

  mutating func glyphSelector(_ value: GraphicsGlyphSelector) {
    switch value {
    case .character(let code):
      token("character")
      integer(code)
    case .name(let name):
      token("name")
      token(name)
    case .index(let index):
      token("index")
      integer(index)
    case .cid(let cid):
      token("cid")
      integer(cid)
    }
  }
}
