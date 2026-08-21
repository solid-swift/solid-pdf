import Foundation
import SolidPostScript
import SolidRaster

/// A native raster target that produces ordered device-colorant plates and a diagnostic preview.
public struct RasterSeparationTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = RasterSeparatedPage
  public typealias Output = [RasterSeparatedPage]
  public typealias ColorEngine = NativeGraphicsColorEngine
  public typealias DeviceRenderingEngine = NativeGraphicsDeviceRenderingEngine
  public typealias TrappingEngine = NativeGraphicsTrappingEngine
  public typealias PageDeviceProvider = RasterSeparationPageDeviceProvider

  /// A renderer dedicated to one separated raster job.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RasterSeparatedPage
    public typealias Output = [RasterSeparatedPage]
    public typealias ColorSession = NativeGraphicsColorSession
    public typealias DeviceRenderingSession = NativeGraphicsDeviceRenderingSession
    public typealias TrappingSession = NativeGraphicsTrappingSession

    public private(set) var pages: [RasterSeparatedPage] = []

    private let preview: RasterImageTarget.Renderer
    private let colorSession: NativeGraphicsColorSession
    private let deviceRenderingSession: NativeGraphicsDeviceRenderingSession
    private let trappingSession: NativeGraphicsTrappingSession
    private var activeDevice: GraphicsDeviceSnapshot
    private var descriptor: GraphicsDeviceDescriptor
    private var rasterMatrix: GraphicsMatrix
    private var colorantCanvas: RasterColorantCanvas?
    private var renderingEnabled = true
    private var activeImage: (
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      components: [Float],
      sourceComponents: [Float],
      maskOpacities: [Float]
    )?
    private var cachedGraphicsClip: GraphicsClip?
    private var cachedRasterClip: RasterClip?
    private let storage = GraphicsStorageTracker()

    fileprivate init(
      preview: RasterImageTarget.Renderer,
      device: GraphicsDeviceSnapshot,
      colorSession: NativeGraphicsColorSession,
      deviceRenderingSession: NativeGraphicsDeviceRenderingSession,
      trappingSession: NativeGraphicsTrappingSession
    ) {
      self.preview = preview
      self.colorSession = colorSession
      self.deviceRenderingSession = deviceRenderingSession
      self.trappingSession = trappingSession
      activeDevice = device
      descriptor = device.descriptor
      rasterMatrix = Self.makeRasterMatrix(device.descriptor)
    }

    /// Processes one validated graphics event for both the diagnostic and plate renderers.
    public func process(_ event: GraphicsEvent) throws {
      activeDevice = event.after.device
      if case .page = event.operation {
        try transmitPage(event, copies: 1)
        return
      }
      try preview.process(event)
      guard renderingEnabled else { return }
      switch event.operation {
      case .paint(.erasePage):
        try clearPage()
      case .paint(.fill(let rule)), .paint(.userPathFill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before)
      case .paint(.stroke):
        try stroke(event.before.path, matrix: event.before.matrix, state: event.before)
      case .paint(.userPathStroke):
        try fill(event.before.path, rule: .winding, state: event.before)
      case .paint(.fillRectangles(let paths)):
        try fill(GraphicsPath(elements: paths.flatMap(\.elements)), rule: .winding, state: event.before)
      case .paint(.strokeRectangles(let paths, let matrix)):
        try stroke(
          GraphicsPath(elements: paths.flatMap(\.elements)),
          matrix: matrix?.concatenated(with: event.before.matrix) ?? event.before.matrix,
          state: event.before
        )
      case .paint(.shading(let shading)):
        try paintShading(shading, clip: event.before.clip, state: event.before)
      case .paint(.form(let form)):
        try paintForm(form, depth: 0)
      case .paint(.text(let run)):
        try paintText(run, state: event.before, depth: 0)
      default:
        break
      }
    }

    /// Begins one ordered sampled-image transfer.
    public func beginImage(_ event: GraphicsEvent) throws {
      try preview.beginImage(event)
      guard case .paint(.image(let descriptor)) = event.operation, activeImage == nil else {
        throw SolidPostScript.Error.ioError
      }
      do {
        try storage.beginImage()
      } catch {
        preview.abortImage()
        throw error
      }
      activeImage = (descriptor, event.before, [], [], [])
    }

    /// Receives complete sampled-image rows in order.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      try preview.writeImageRows(rows)
      guard var image = activeImage else { throw SolidPostScript.Error.ioError }
      let components = rows.components.count.addingReportingOverflow(rows.sourceComponents?.count ?? 0)
      guard !components.overflow else { throw GraphicsStorageAccountingError.limitExceeded }
      let bytes = components.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      guard !bytes.overflow else { throw GraphicsStorageAccountingError.limitExceeded }
      try storage.appendImageBytes(bytes.partialValue)
      image.components.append(contentsOf: rows.components)
      image.sourceComponents.append(contentsOf: rows.sourceComponents ?? [])
      activeImage = image
    }

    /// Receives complete opacity-mask rows in order.
    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
      try preview.writeImageMaskRows(rows)
      guard var image = activeImage else { throw SolidPostScript.Error.ioError }
      let bytes = rows.opacities.count.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      guard !bytes.overflow else { throw GraphicsStorageAccountingError.limitExceeded }
      try storage.appendImageBytes(bytes.partialValue)
      image.maskOpacities.append(contentsOf: rows.opacities)
      activeImage = image
    }

    /// Completes and paints the current sampled image.
    public func endImage() throws {
      try preview.endImage()
      guard let image = activeImage else { throw SolidPostScript.Error.ioError }
      activeImage = nil
      defer { storage.abortImage() }
      guard renderingEnabled else { return }
      try paintImage(GraphicsImage(
        descriptor: image.descriptor,
        components: image.components,
        sourceComponents: image.sourceComponents.isEmpty ? nil : image.sourceComponents,
        mask: try graphicsMask(descriptor: image.descriptor, opacities: image.maskOpacities)
      ), state: image.state)
    }

    /// Abandons the current sampled-image transfer.
    public func abortImage() {
      preview.abortImage()
      activeImage = nil
      storage.abortImage()
    }

    public func installStorageAccounting(_ session: GraphicsStorageAccountingSession) {
      storage.install(session)
      preview.installStorageAccounting(session)
    }

    /// Activates a negotiated page or null device.
    public func activateDevice(_ device: GraphicsDeviceSnapshot) throws {
      activeDevice = device
      try preview.activateDevice(device)
      if device.kind == .null {
        renderingEnabled = false
        return
      }
      renderingEnabled = true
      descriptor = device.descriptor
      rasterMatrix = Self.makeRasterMatrix(device.descriptor)
      colorantCanvas = nil
      cachedGraphicsClip = nil
      cachedRasterClip = nil
    }

    /// Releases renderer state belonging to a deactivated device.
    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws {
      preview.deactivateDevice(device)
      if activeDevice.identifier == device.identifier { colorantCanvas = nil }
    }

    /// Transmits a completed page and its ordered immutable plates.
    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      guard copies >= 0 else { throw SolidPostScript.Error.ioError }
      let previousCount = preview.pages.count
      try preview.transmitPage(event, copies: copies)
      let images = Array(preview.pages.dropFirst(previousCount))
      guard copies > 0 else {
        colorantCanvas = nil
        return
      }
      let planes = try finishColorantPage()
      let plates = activeDevice.descriptor.colorants.producesSeparations
        ? try orderedPlates(planes)
        : []
      let diagnostic = try makePreview(planes)
      for _ in images {
        pages.append(RasterSeparatedPage(
          device: activeDevice,
          plates: plates,
          compositePreview: diagnostic
        ))
      }
    }

    /// Completes the render and returns all transmitted separated pages.
    public func finish() throws -> sending [RasterSeparatedPage] {
      _ = try preview.finish()
      activeImage = nil
      colorantCanvas = nil
      let result = pages
      pages.removeAll()
      return result
    }

    /// Abandons the render and releases its page storage.
    public func abort() {
      preview.abort()
      activeImage = nil
      colorantCanvas = nil
      pages.removeAll()
    }
  }

  /// The initial page geometry and device capabilities.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The native portable color conversion engine.
  public let colorEngine: NativeGraphicsColorEngine
  /// The native transfer and halftone engine.
  public let deviceRenderingEngine = NativeGraphicsDeviceRenderingEngine()
  /// The native Type 1001 trapping engine.
  public let trappingEngine = NativeGraphicsTrappingEngine()
  /// The adaptive or fixed separation page-device provider.
  public let pageDeviceProvider: RasterSeparationPageDeviceProvider

  /// Creates a separation target, defaulting to ordered CMYK plates.
  public init(
    deviceDescriptor: GraphicsDeviceDescriptor = .letter,
    colorantConfiguration: GraphicsColorantConfiguration? = nil,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive
  ) {
    let colorants = colorantConfiguration ?? GraphicsColorantConfiguration(
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
      colorants: colorants,
      trapping: .rasterType1001
    )
    colorEngine = NativeGraphicsColorEngine()
    pageDeviceProvider = RasterSeparationPageDeviceProvider(mode: pageDeviceMode)
  }

  /// Creates a renderer with target-created color and device-rendering sessions.
  public func makeRenderer() throws -> sending Renderer {
    let colorSession = try colorEngine.makeSession(for: deviceDescriptor)
    let renderingSession = deviceRenderingEngine.makeSession(for: deviceDescriptor)
    return try makeRenderer(colorSession: colorSession, deviceRenderingSession: renderingSession)
  }

  /// Creates a renderer with a caller-supplied color session.
  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession
  ) throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingEngine.makeSession(for: deviceDescriptor)
    )
  }

  /// Creates a renderer with caller-supplied color and device-rendering sessions.
  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession,
    deviceRenderingSession: sending NativeGraphicsDeviceRenderingSession
  ) throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingSession,
      fontSession: SemanticGraphicsFontSession(),
      trappingSession: trappingEngine.makeSession(for: deviceDescriptor)
    )
  }

  /// Creates a renderer with all caller-supplied render-scoped services.
  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession,
    deviceRenderingSession: sending NativeGraphicsDeviceRenderingSession,
    fontSession: sending SemanticGraphicsFontSession,
    trappingSession: sending NativeGraphicsTrappingSession
  ) throws -> sending Renderer {
    guard deviceDescriptor.colorants.processModel != .deviceN
      || deviceDescriptor.colorants.hasUsableDeviceNLookup
    else { throw SolidPostScript.Error.configurationError }
    let target = RasterImageTarget(
      pixelWidth: Int(deviceDescriptor.mediaBounds.width.rounded()),
      pixelHeight: Int(deviceDescriptor.mediaBounds.height.rounded()),
      deviceDescriptor: deviceDescriptor
    )
    let previewColorSession = try colorEngine.makeSession(for: deviceDescriptor)
    let previewRenderingSession = deviceRenderingEngine.makeSession(for: deviceDescriptor)
    let preview = try target.makeRenderer(
      colorSession: previewColorSession,
      deviceRenderingSession: previewRenderingSession
    )
    let snapshot = GraphicsDeviceSnapshot(
      identifier: GraphicsDeviceIdentifier(),
      kind: .page,
      descriptor: deviceDescriptor,
      pageNumber: 0,
      numberOfCopies: 1
    )
    return Renderer(
      preview: preview,
      device: snapshot,
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingSession,
      trappingSession: trappingSession
    )
  }
}

private extension RasterSeparationTarget.Renderer {
  static func makeRasterMatrix(_ descriptor: GraphicsDeviceDescriptor) -> GraphicsMatrix {
    GraphicsMatrix(
      a: 1,
      b: 0,
      c: 0,
      d: -1,
      tx: -descriptor.mediaBounds.x,
      ty: descriptor.mediaBounds.maxY
    )
  }

  func withColorantCanvas(_ body: (inout RasterColorantCanvas) throws -> Void) throws {
    var canvas = try takeColorantCanvas()
    do {
      try body(&canvas)
      colorantCanvas = consume canvas
    } catch {
      colorantCanvas = consume canvas
      if error is RasterError { throw SolidPostScript.Error.ioError }
      throw error
    }
  }

  func takeColorantCanvas() throws -> RasterColorantCanvas {
    if let canvas = colorantCanvas.take() { return consume canvas }
    do {
      var canvas = try RasterColorantCanvas(
        width: Int(descriptor.mediaBounds.width.rounded()),
        height: Int(descriptor.mediaBounds.height.rounded()),
        colorants: descriptor.colorants.availableColorants.map(\.name)
      )
      try canvas.configureTrapping(try trappingSession.resolve(activeDevice.trapping, for: descriptor))
      return consume canvas
    } catch {
      throw SolidPostScript.Error.ioError
    }
  }

  func finishColorantPage() throws -> [RasterColorantPlane] {
    let canvas = try takeColorantCanvas()
    do {
      let planes = try canvas.finish()
      colorantCanvas = nil
      return planes
    } catch {
      colorantCanvas = nil
      throw SolidPostScript.Error.ioError
    }
  }

  func clearPage() throws {
    try withColorantCanvas { try $0.clear() }
  }

  func rasterClip(_ clip: GraphicsClip) throws(RasterError) -> RasterClip {
    if clip == cachedGraphicsClip, let cachedRasterClip { return cachedRasterClip }
    let converted = RasterClip(
      imageableBounds: transformedBounds(clip.imageableBounds, by: rasterMatrix).raster,
      constraints: clip.constraints.map {
        RasterClipConstraint(
          path: $0.path.transformed(by: rasterMatrix).rasterPath,
          rule: $0.rule.raster
        )
      }
    )
    cachedGraphicsClip = clip
    cachedRasterClip = converted
    return converted
  }

  func transformedBounds(_ rect: GraphicsRect, by matrix: GraphicsMatrix) -> GraphicsRect {
    let points = [
      matrix.transform(GraphicsPoint(x: rect.x, y: rect.y)),
      matrix.transform(GraphicsPoint(x: rect.maxX, y: rect.y)),
      matrix.transform(GraphicsPoint(x: rect.maxX, y: rect.maxY)),
      matrix.transform(GraphicsPoint(x: rect.x, y: rect.maxY)),
    ]
    let minimumX = points.map(\.x).min() ?? 0
    let maximumX = points.map(\.x).max() ?? 0
    let minimumY = points.map(\.y).min() ?? 0
    let maximumY = points.map(\.y).max() ?? 0
    return GraphicsRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
  }

  func rasterPaint(_ paint: GraphicsPaint, state: GraphicsStateSnapshot) throws -> RasterColorantPaint {
    let resolved = try colorSession.resolveColorants(paint, configuration: descriptor.colorants)
    let overprint = state.overprint && descriptor.colorants.supportsOverprint
    return RasterColorantPaint(
      tints: Dictionary(uniqueKeysWithValues: resolved.components.compactMap {
        overprint && $0.tint == 0 ? nil : ($0.name, $0.tint)
      }),
      overprintsUnspecifiedColorants: overprint,
      paintsNothing: resolved.paintsNothing
    )
  }

  func fill(
    _ path: GraphicsPath,
    rule: GraphicsFillRule,
    state: GraphicsStateSnapshot,
    paint: GraphicsPaint? = nil,
    clip: GraphicsClip? = nil,
    depth: Int = 0,
    markKind: RasterTrappingMarkKind = .vector
  ) throws {
    let state = state.replacingDevice(activeDevice)
    let effectivePaint = paint ?? state.paint
    if case .pattern(let pattern) = effectivePaint {
      try paintPattern(
        pattern,
        through: path,
        rule: rule,
        clip: clip ?? state.clip,
        state: state,
        depth: depth
      )
      return
    }
    let program = try deviceRenderingSession.resolve(state.deviceRendering, for: descriptor)
    try withColorantCanvas { canvas in
      try canvas.configureTrapping(try trappingSession.resolve(state.device.trapping, for: descriptor))
      try canvas.setClip(try rasterClip(clip ?? state.clip))
      try canvas.fill(
        path.transformed(by: rasterMatrix).rasterPath,
        rule: rule.raster,
        paint: try rasterPaint(effectivePaint, state: state),
        deviceRendering: program,
        markKind: markKind
      )
    }
  }

  func stroke(
    _ path: GraphicsPath,
    matrix: GraphicsMatrix,
    state: GraphicsStateSnapshot
  ) throws {
    let state = state.replacingDevice(activeDevice)
    if case .pattern = state.paint {
      let outline = try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
      try fill(outline, rule: .winding, state: state)
      return
    }
    if state.strokeAdjustment {
      let outline = try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
      try fill(outline, rule: .winding, state: state)
      return
    }
    guard let inverse = matrix.inverted else { return }
    let program = try deviceRenderingSession.resolve(state.deviceRendering, for: descriptor)
    let style = RasterStrokeStyle(
      width: state.lineWidth,
      cap: state.lineCap.raster,
      join: state.lineJoin.raster,
      miterLimit: state.miterLimit,
      dash: state.dash.pattern,
      dashPhase: state.dash.phase
    )
    try withColorantCanvas { canvas in
      try canvas.configureTrapping(try trappingSession.resolve(state.device.trapping, for: descriptor))
      try canvas.setClip(try rasterClip(state.clip))
      try canvas.stroke(
        path.transformed(by: inverse).rasterPath,
        style: style,
        paint: try rasterPaint(state.paint, state: state),
        transform: matrix.concatenated(with: rasterMatrix).raster,
        deviceRendering: program
      )
    }
  }

  func paintShading(
    _ shading: GraphicsShading,
    clip: GraphicsClip,
    state: GraphicsStateSnapshot
  ) throws {
    let state = state.replacingDevice(activeDevice)
    let effectiveClip = GraphicsClip(
      imageableBounds: clip.imageableBounds,
      constraints: clip.constraints + (shading.clipPath.map {
        [GraphicsClipConstraint(path: $0, rule: .winding)]
      } ?? [])
    )
    let paints = shading.mesh.triangles.flatMap { [$0.first.paint, $0.second.paint, $0.third.paint] }
    let resolved = try colorSession.resolveColorants(paints, configuration: descriptor.colorants)
    let overprint = state.overprint && descriptor.colorants.supportsOverprint
    func converted(_ paint: GraphicsColorantPaint) -> RasterColorantPaint {
      RasterColorantPaint(
        tints: Dictionary(uniqueKeysWithValues: paint.components.compactMap {
          overprint && $0.tint == 0 ? nil : ($0.name, $0.tint)
        }),
        overprintsUnspecifiedColorants: overprint,
        paintsNothing: paint.paintsNothing
      )
    }
    var offset = 0
    let triangles = shading.mesh.triangles.map { triangle -> RasterColorantGradientTriangle in
      defer { offset += 3 }
      return RasterColorantGradientTriangle(
        first: .init(
          position: rasterMatrix.transform(triangle.first.position).raster,
          paint: converted(resolved[offset])
        ),
        second: .init(
          position: rasterMatrix.transform(triangle.second.position).raster,
          paint: converted(resolved[offset + 1])
        ),
        third: .init(
          position: rasterMatrix.transform(triangle.third.position).raster,
          paint: converted(resolved[offset + 2])
        )
      )
    }
    let program = try deviceRenderingSession.resolve(state.deviceRendering, for: descriptor)
    try withColorantCanvas { canvas in
      try canvas.configureTrapping(try trappingSession.resolve(state.device.trapping, for: descriptor))
      try canvas.setClip(try rasterClip(effectiveClip))
      if let background = shading.background {
        try canvas.fill(
          GraphicsPath.rectangle(descriptor.mediaBounds).transformed(by: rasterMatrix).rasterPath,
          rule: .winding,
          paint: try rasterPaint(background, state: state),
          deviceRendering: program
        )
      }
      try canvas.paint(RasterColorantGradientMesh(triangles: triangles), deviceRendering: program)
    }
  }

  func paintForm(_ form: GraphicsForm, depth: Int) throws {
    guard depth < 16 else { throw SolidPostScript.Error.ioError }
    for effect in form.displayList.effects { try replayFormEffect(effect, depth: depth + 1) }
  }

  func replayFormEffect(_ effect: GraphicsEffect, depth: Int) throws {
    switch effect {
    case .fill(let path, let rule, let state), .userPathFill(let path, let rule, let state):
      try fill(path, rule: rule, state: state, depth: depth)
    case .stroke(let path, let state):
      try stroke(path, matrix: state.matrix, state: state)
    case .userPathStroke(let outline, let state):
      try fill(outline, rule: .winding, state: state, depth: depth)
    case .erase:
      try clearPage()
    case .fillRectangles(let paths, let state):
      try fill(GraphicsPath(elements: paths.flatMap(\.elements)), rule: .winding, state: state, depth: depth)
    case .strokeRectangles(let paths, let matrix, let state):
      try stroke(
        GraphicsPath(elements: paths.flatMap(\.elements)),
        matrix: matrix?.concatenated(with: state.matrix) ?? state.matrix,
        state: state
      )
    case .image(let image, let state):
      try paintImage(image, state: state)
    case .shading(let shading, let state):
      try paintShading(shading, clip: state.clip, state: state)
    case .form(let form, _):
      try paintForm(form, depth: depth)
    case .text(let run, let state):
      try paintText(run, state: state, depth: depth)
    }
  }

  func paintText(_ run: GraphicsGlyphRun, state: GraphicsStateSnapshot, depth: Int) throws {
    let state = state.replacingDevice(activeDevice)
    guard depth < 16 else { throw SolidPostScript.Error.ioError }
    for placement in run.glyphs {
      switch placement.glyph.program {
      case .outline(let path):
        try fill(
          path.transformed(by: placement.transform),
          rule: .winding,
          state: state,
          depth: depth,
          markKind: .text
        )
      case .displayList(let list):
        for effect in list.effects { try replayFormEffect(effect, depth: depth + 1) }
      case .bitmap, .empty, .missing:
        break
      }
    }
  }
}

private extension RasterSeparationTarget.Renderer {
  func paintPattern(
    _ paint: GraphicsPatternPaint,
    through path: GraphicsPath,
    rule: GraphicsFillRule,
    clip: GraphicsClip,
    state: GraphicsStateSnapshot,
    depth: Int
  ) throws {
    guard depth < 16 else { throw SolidPostScript.Error.ioError }
    switch paint {
    case .empty:
      return
    case .shading(let shading):
      try paintShading(
        shading,
        clip: GraphicsClip(
          imageableBounds: clip.imageableBounds,
          constraints: clip.constraints + [GraphicsClipConstraint(path: path, rule: rule)]
        ),
        state: state
      )
    case .tiling(let pattern, let underlying):
      let translations = try tileTranslations(for: pattern)
      guard translations.count <= 1_000_000 else { throw SolidPostScript.Error.ioError }
      for translation in translations {
        for effect in pattern.displayList.effects {
          try replayPatternEffect(
            effect,
            translatedBy: translation,
            underlying: underlying,
            through: path,
            rule: rule,
            clip: clip,
            depth: depth + 1
          )
        }
      }
    }
  }

  func replayPatternEffect(
    _ effect: GraphicsEffect,
    translatedBy translation: GraphicsMatrix,
    underlying: GraphicsPaint?,
    through paintedPath: GraphicsPath,
    rule paintedRule: GraphicsFillRule,
    clip: GraphicsClip,
    depth: Int
  ) throws {
    guard depth < 16 else { throw SolidPostScript.Error.ioError }
    if case .form(let form, _) = effect {
      for nested in form.displayList.effects {
        try replayPatternEffect(
          nested,
          translatedBy: translation,
          underlying: underlying,
          through: paintedPath,
          rule: paintedRule,
          clip: clip,
          depth: depth + 1
        )
      }
      return
    }
    if case .image(let image, let imageState) = effect {
      let combinedClip = translatedPatternClip(
        imageState.clip,
        translatedBy: translation,
        through: paintedPath,
        rule: paintedRule,
        outer: clip
      )
      let kind: GraphicsImageKind = switch image.descriptor.kind {
      case .color(let space): .color(space)
      case .mask(let paint): .mask(underlying ?? paint)
      }
      let transformedDescriptor = GraphicsImageDescriptor(
        width: image.descriptor.width,
        height: image.descriptor.height,
        kind: kind,
        sourceColorSpace: image.descriptor.sourceColorSpace,
        imageToDevice: image.descriptor.imageToDevice.concatenated(with: translation),
        interpolate: image.descriptor.interpolate,
        mask: image.descriptor.mask?.transformed(by: translation)
      )
      try paintImage(
        GraphicsImage(
          descriptor: transformedDescriptor,
          components: image.components,
          sourceComponents: image.sourceComponents,
          mask: image.mask.map {
            GraphicsImageMask(
              descriptor: $0.descriptor.transformed(by: translation),
              opacities: $0.opacities
            )
          }
        ),
        state: replacingClip(in: imageState, with: combinedClip)
      )
      return
    }
    if case .text(let run, let textState) = effect {
      for placement in run.glyphs {
        switch placement.glyph.program {
        case .outline(let path):
          try replayPatternEffect(
            .fill(path: path.transformed(by: placement.transform), rule: .winding, state: textState),
            translatedBy: translation,
            underlying: underlying,
            through: paintedPath,
            rule: paintedRule,
            clip: clip,
            depth: depth + 1
          )
        case .displayList(let list):
          for nested in list.effects {
            try replayPatternEffect(
              nested,
              translatedBy: translation,
              underlying: underlying,
              through: paintedPath,
              rule: paintedRule,
              clip: clip,
              depth: depth + 1
            )
          }
        case .bitmap, .empty, .missing:
          break
        }
      }
      return
    }

    let effectPath: GraphicsPath
    let effectRule: GraphicsFillRule
    let effectState: GraphicsStateSnapshot
    switch effect {
    case .fill(let path, let rule, let state), .userPathFill(let path, let rule, let state):
      effectPath = path.transformed(by: translation)
      effectRule = rule
      effectState = state
    case .stroke(let path, let state):
      effectPath = try GraphicsPathGeometry.strokeOutline(path: path, state: state).transformed(by: translation)
      effectRule = .winding
      effectState = state
    case .userPathStroke(let outline, let state):
      effectPath = outline.transformed(by: translation)
      effectRule = .winding
      effectState = state
    case .erase(let state):
      effectPath = GraphicsPath.rectangle(descriptor.mediaBounds).transformed(by: translation)
      effectRule = .winding
      effectState = state
    case .fillRectangles(let paths, let state):
      effectPath = GraphicsPath(elements: paths.flatMap(\.elements)).transformed(by: translation)
      effectRule = .winding
      effectState = state
    case .strokeRectangles(let paths, let matrix, let state):
      effectPath = try GraphicsPathGeometry.strokeOutline(
        path: GraphicsPath(elements: paths.flatMap(\.elements)),
        state: state,
        matrix: matrix?.concatenated(with: state.matrix) ?? state.matrix
      ).transformed(by: translation)
      effectRule = .winding
      effectState = state
    case .shading(let shading, let state):
      let transformed = GraphicsShading(
        type: shading.type,
        colorSpace: shading.colorSpace,
        background: shading.background,
        bounds: shading.bounds,
        clipPath: shading.clipPath?.transformed(by: translation),
        antialias: shading.antialias,
        geometry: shading.geometry,
        mesh: GraphicsShadingMesh(triangles: shading.mesh.triangles.map { triangle in
          GraphicsShadingTriangle(
            first: .init(position: translation.transform(triangle.first.position), paint: triangle.first.paint),
            second: .init(position: translation.transform(triangle.second.position), paint: triangle.second.paint),
            third: .init(position: translation.transform(triangle.third.position), paint: triangle.third.paint)
          )
        })
      )
      try paintShading(
        transformed,
        clip: translatedPatternClip(
          state.clip,
          translatedBy: translation,
          through: paintedPath,
          rule: paintedRule,
          outer: clip
        ),
        state: state
      )
      return
    case .image, .form:
      preconditionFailure("Handled before vector replay")
    case .text:
      preconditionFailure("Text effects are handled before vector replay")
    }

    let combinedClip = translatedPatternClip(
      effectState.clip,
      translatedBy: translation,
      through: paintedPath,
      rule: paintedRule,
      outer: clip
    )
    try fill(
      effectPath,
      rule: effectRule,
      state: effectState,
      paint: underlying ?? effectState.paint,
      clip: combinedClip,
      depth: depth
    )
  }

  func translatedPatternClip(
    _ inner: GraphicsClip,
    translatedBy translation: GraphicsMatrix,
    through path: GraphicsPath,
    rule: GraphicsFillRule,
    outer: GraphicsClip
  ) -> GraphicsClip {
    GraphicsClip(
      imageableBounds: outer.imageableBounds,
      constraints: outer.constraints
        + [GraphicsClipConstraint(path: path, rule: rule)]
        + inner.constraints.map {
          GraphicsClipConstraint(path: $0.path.transformed(by: translation), rule: $0.rule)
        }
    )
  }

  func tileTranslations(for pattern: GraphicsTilingPattern) throws -> [GraphicsMatrix] {
    let origin = pattern.matrix.transform(GraphicsPoint(x: 0, y: 0))
    let requestedX = pattern.matrix.transformDistance(GraphicsPoint(x: pattern.xStep, y: 0))
    let requestedY = pattern.matrix.transformDistance(GraphicsPoint(x: 0, y: pattern.yStep))
    let xStep = pattern.tilingType == 2 ? requestedX : adjustedLatticeStep(requestedX)
    let yStep = pattern.tilingType == 2 ? requestedY : adjustedLatticeStep(requestedY)
    let lattice = GraphicsMatrix(a: xStep.x, b: xStep.y, c: yStep.x, d: yStep.y, tx: origin.x, ty: origin.y)
    guard let inverse = lattice.inverted else { throw SolidPostScript.Error.ioError }
    let media = descriptor.mediaBounds
    let points = [
      GraphicsPoint(x: media.x, y: media.y), GraphicsPoint(x: media.maxX, y: media.y),
      GraphicsPoint(x: media.maxX, y: media.maxY), GraphicsPoint(x: media.x, y: media.maxY),
    ].map(inverse.transform)
    let minimumX = Int(((points.map(\.x).min() ?? 0) - 1).rounded(.down))
    let maximumX = Int(((points.map(\.x).max() ?? 0) + 1).rounded(.up))
    let minimumY = Int(((points.map(\.y).min() ?? 0) - 1).rounded(.down))
    let maximumY = Int(((points.map(\.y).max() ?? 0) + 1).rounded(.up))
    let columns = maximumX - minimumX + 1
    let rows = maximumY - minimumY + 1
    guard columns > 0, rows > 0, rows <= 1_000_000 / columns else {
      throw SolidPostScript.Error.ioError
    }
    return (minimumY...maximumY).flatMap { row in
      (minimumX...maximumX).map { column in
        let tx = Double(column) * xStep.x + Double(row) * yStep.x
        let ty = Double(column) * xStep.y + Double(row) * yStep.y
        return GraphicsMatrix(
          a: 1,
          b: 0,
          c: 0,
          d: 1,
          tx: pattern.tilingType == 2 ? tx.rounded() : tx,
          ty: pattern.tilingType == 2 ? ty.rounded() : ty
        )
      }
    }
  }

  func adjustedLatticeStep(_ value: GraphicsPoint) -> GraphicsPoint {
    var x = value.x.rounded()
    var y = value.y.rounded()
    if x == 0, y == 0 {
      if abs(value.x) >= abs(value.y) {
        x = value.x.sign == .minus ? -1 : 1
      } else {
        y = value.y.sign == .minus ? -1 : 1
      }
    }
    return GraphicsPoint(x: x, y: y)
  }

  func replacingClip(
    in state: GraphicsStateSnapshot,
    with clip: GraphicsClip
  ) -> GraphicsStateSnapshot {
    GraphicsStateSnapshot(
      matrix: state.matrix,
      path: state.path,
      clip: clip,
      paint: state.paint,
      colorSpace: state.colorSpace,
      colorComponents: state.colorComponents,
      overprint: state.overprint,
      lineWidth: state.lineWidth,
      lineCap: state.lineCap,
      lineJoin: state.lineJoin,
      miterLimit: state.miterLimit,
      dash: state.dash,
      flatness: state.flatness,
      strokeAdjustment: state.strokeAdjustment,
      smoothness: state.smoothness,
      pathBoundingBox: state.pathBoundingBox,
      device: state.device,
      deviceRendering: state.deviceRendering
    )
  }
}

private extension RasterSeparationTarget.Renderer {
  func orderedPlates(_ planes: [RasterColorantPlane]) throws -> [RasterSeparationPlate] {
    let indexed = Dictionary(uniqueKeysWithValues: planes.map { ($0.name, $0.mask) })
    return try descriptor.colorants.effectiveSeparationOrder.map { name in
      guard let mask = indexed[name] else { throw SolidPostScript.Error.ioError }
      return RasterSeparationPlate(colorant: name, tint: mask)
    }
  }

  func makePreview(_ planes: [RasterColorantPlane]) throws -> RasterImage {
    guard let first = planes.first else { throw SolidPostScript.Error.ioError }
    let count = first.mask.width * first.mask.height
    var bytes = Data(repeating: 255, count: count * 4)
    let indexed = Dictionary(uniqueKeysWithValues: planes.map { ($0.name, $0.mask) })
    for index in 0..<count {
      let process = processPreview(at: index, planes: indexed)
      let offset = index * 4
      bytes[offset] = UInt8((process.red * 255).rounded())
      bytes[offset + 1] = UInt8((process.green * 255).rounded())
      bytes[offset + 2] = UInt8((process.blue * 255).rounded())
    }
    for colorant in descriptor.colorants.additionalColorants {
      guard let plane = indexed[colorant.name] else { continue }
      let ink = colorant.previewColor
      let red = ink?.red ?? 0
      let green = ink?.green ?? 0
      let blue = ink?.blue ?? 0
      for index in 0..<count {
        let tint = Double(plane.data[index]) / 255
        let offset = index * 4
        bytes[offset] = UInt8((Double(bytes[offset]) * (1 - tint * (1 - red))).rounded())
        bytes[offset + 1] = UInt8((Double(bytes[offset + 1]) * (1 - tint * (1 - green))).rounded())
        bytes[offset + 2] = UInt8((Double(bytes[offset + 2]) * (1 - tint * (1 - blue))).rounded())
      }
    }
    do {
      return try RasterImage(
        width: first.mask.width,
        height: first.mask.height,
        bytesPerRow: first.mask.width * 4,
        pixelFormat: .rgba8Unorm,
        data: bytes
      )
    } catch {
      throw SolidPostScript.Error.ioError
    }
  }

  func processPreview(
    at index: Int,
    planes: [String: RasterMask]
  ) -> (red: Double, green: Double, blue: Double) {
    func tint(_ name: String) -> Double {
      planes[name].map { Double($0.data[index]) / 255 } ?? 0
    }
    switch descriptor.colorants.processModel {
    case .deviceGray:
      let value = 1 - tint("Gray")
      return (value, value, value)
    case .deviceRGB:
      return (1 - tint("Red"), 1 - tint("Green"), 1 - tint("Blue"))
    case .deviceCMY:
      return (1 - tint("Cyan"), 1 - tint("Magenta"), 1 - tint("Yellow"))
    case .deviceCMYK:
      let black = tint("Black")
      return (
        1 - min(1, tint("Cyan") + black),
        1 - min(1, tint("Magenta") + black),
        1 - min(1, tint("Yellow") + black)
      )
    case .deviceRGBK:
      let gray = tint("Gray")
      return (
        1 - min(1, tint("Red") + gray),
        1 - min(1, tint("Green") + gray),
        1 - min(1, tint("Blue") + gray)
      )
    case .deviceN:
      return (1, 1, 1)
    }
  }

  func graphicsMask(
    descriptor: GraphicsImageDescriptor,
    opacities: [Float]
  ) throws -> GraphicsImageMask? {
    guard let mask = descriptor.mask else { return nil }
    let expected: Int = switch mask {
    case .explicit(let width, let height, _, _): width * height
    case .colorKey: descriptor.width * descriptor.height
    }
    guard opacities.count <= expected else { throw SolidPostScript.Error.ioError }
    return GraphicsImageMask(
      descriptor: mask,
      opacities: opacities + Array(repeating: 0, count: expected - opacities.count)
    )
  }

  func paintImage(_ image: GraphicsImage, state: GraphicsStateSnapshot) throws {
    let state = state.replacingDevice(activeDevice)
    let rowCount = image.completedRowCount
    guard rowCount > 0 else { return }
    let (planes, stencil) = try imagePlanes(image, rowCount: rowCount, state: state)
    guard !planes.isEmpty else { return }
    let explicitMask = try rasterMask(image.mask, descriptor: image.descriptor)
    let selectedMask = stencil ?? explicitMask
    let maskTransform: GraphicsMatrix?
    let maskInterpolation: Bool
    if stencil != nil {
      maskTransform = image.descriptor.imageToDevice
      maskInterpolation = image.descriptor.interpolate
    } else if case .explicit(_, _, let transform, let interpolate) = image.descriptor.mask {
      maskTransform = transform
      maskInterpolation = interpolate
    } else if explicitMask != nil {
      maskTransform = image.descriptor.imageToDevice
      maskInterpolation = image.descriptor.interpolate
    } else {
      maskTransform = nil
      maskInterpolation = false
    }
    let program = try deviceRenderingSession.resolve(state.deviceRendering, for: descriptor)
    try withColorantCanvas { canvas in
      try canvas.configureTrapping(try trappingSession.resolve(state.device.trapping, for: descriptor))
      try canvas.setClip(try rasterClip(state.clip))
      try canvas.draw(
        planes,
        transform: image.descriptor.imageToDevice.concatenated(with: rasterMatrix).raster,
        interpolation: image.descriptor.interpolate ? .linear : .nearest,
        mask: selectedMask,
        maskTransform: maskTransform?.concatenated(with: rasterMatrix).raster,
        maskInterpolation: maskInterpolation ? .linear : .nearest,
        overprintsUnspecifiedColorants: state.overprint && descriptor.colorants.supportsOverprint,
        deviceRendering: program
      )
    }
  }

  func imagePlanes(
    _ image: GraphicsImage,
    rowCount: Int,
    state: GraphicsStateSnapshot
  ) throws -> (planes: [RasterColorantPlane], stencil: RasterMask?) {
    let width = image.descriptor.width
    let pixelCount = width * rowCount
    switch image.descriptor.kind {
    case .mask(let paint):
      let resolved = try colorSession.resolveColorants(paint, configuration: descriptor.colorants)
      let planes = try resolved.components.map { component in
        RasterColorantPlane(
          name: component.name,
          mask: try RasterMask(
            width: width,
            height: rowCount,
            bytesPerRow: width,
            data: Data(repeating: UInt8((component.tint * 255).rounded()), count: pixelCount)
          )
        )
      }
      var opacity = Data(repeating: 0, count: pixelCount)
      for index in 0..<min(pixelCount, image.components.count) {
        opacity[index] = UInt8((min(1, max(0, image.components[index])) * 255).rounded())
      }
      return (planes, try RasterMask(width: width, height: rowCount, bytesPerRow: width, data: opacity))
    case .color(let colorSpace):
      let available = Set(descriptor.colorants.availableColorants.map(\.name))
      let direct: (names: [String], components: [Float])? = if let source = image.descriptor.sourceColorSpace,
        let sourceComponents = image.sourceComponents
      {
        switch source {
        case .separation(let name, _) where name == "All" || name == "None" || available.contains(name):
          ([name], sourceComponents)
        case .deviceN(let names, _) where names.allSatisfy(available.contains):
          (names, sourceComponents)
        default:
          nil
        }
      } else {
        nil
      }
      let names = direct?.names ?? descriptor.colorants.availableColorants.map(\.name)
      var data = Dictionary(uniqueKeysWithValues: names.filter { $0 != "None" }.map {
        ($0, Data(repeating: 0, count: pixelCount))
      })
      if let direct {
        if direct.names == ["All"] {
          let targetNames = descriptor.colorants.availableColorants.map(\.name)
          data = Dictionary(uniqueKeysWithValues: targetNames.map { ($0, Data(repeating: 0, count: pixelCount)) })
          for pixel in 0..<pixelCount {
            let tint = direct.components[pixel]
            for name in targetNames { data[name]![pixel] = UInt8((min(1, max(0, tint)) * 255).rounded()) }
          }
        } else if direct.names != ["None"] {
          for pixel in 0..<pixelCount {
            for (component, name) in direct.names.enumerated() {
              let tint = direct.components[pixel * direct.names.count + component]
              data[name]![pixel] = UInt8((min(1, max(0, tint)) * 255).rounded())
            }
          }
        }
      } else {
        let componentCount = colorSpace.componentCount
        for pixel in 0..<pixelCount {
          let offset = pixel * componentCount
          guard offset + componentCount <= image.components.count else { break }
          let paint: GraphicsPaint = switch colorSpace {
          case .deviceGray:
            .deviceGray(Double(image.components[offset]))
          case .deviceRGB:
            .deviceRGB(
              red: Double(image.components[offset]),
              green: Double(image.components[offset + 1]),
              blue: Double(image.components[offset + 2])
            )
          case .deviceCMYK:
            .deviceCMYK(
              cyan: Double(image.components[offset]),
              magenta: Double(image.components[offset + 1]),
              yellow: Double(image.components[offset + 2]),
              black: Double(image.components[offset + 3])
            )
          }
          let resolved = try colorSession.resolveColorants(paint, configuration: descriptor.colorants)
          for component in resolved.components {
            data[component.name]?[pixel] = UInt8((component.tint * 255).rounded())
          }
        }
      }
      let planes = try data.map { name, bytes in
        RasterColorantPlane(
          name: name,
          mask: try RasterMask(width: width, height: rowCount, bytesPerRow: width, data: bytes)
        )
      }
      return (planes, nil)
    }
  }

  func rasterMask(
    _ mask: GraphicsImageMask?,
    descriptor: GraphicsImageDescriptor
  ) throws -> RasterMask? {
    guard let mask else { return nil }
    let dimensions: (Int, Int) = switch mask.descriptor {
    case .explicit(let width, let height, _, _): (width, height)
    case .colorKey: (descriptor.width, descriptor.height)
    }
    guard dimensions.0 > 0, dimensions.1 > 0,
      dimensions.0 <= Int.max / dimensions.1,
      mask.opacities.count == dimensions.0 * dimensions.1
    else { throw SolidPostScript.Error.ioError }
    var bytes = Data(repeating: 0, count: mask.opacities.count)
    for index in mask.opacities.indices {
      bytes[index] = UInt8((min(1, max(0, mask.opacities[index])) * 255).rounded())
    }
    do {
      return try RasterMask(
        width: dimensions.0,
        height: dimensions.1,
        bytesPerRow: dimensions.0,
        data: bytes
      )
    } catch {
      throw SolidPostScript.Error.ioError
    }
  }
}
