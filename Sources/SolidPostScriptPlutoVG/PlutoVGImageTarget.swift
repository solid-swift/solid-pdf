import CPlutoVG
import Foundation
import SolidPostScript
import SolidPostScriptRaster
import SolidRaster

/// A portable PostScript graphics target that rasterizes pages through PlutoVG.
public struct PlutoVGImageTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = RasterImage
  public typealias Output = [RasterImage]
  public typealias ColorEngine = NativeGraphicsColorEngine
  public typealias DeviceRenderingEngine = NativeGraphicsDeviceRenderingEngine

  /// The renderer dedicated to one PlutoVG image render.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RasterImage
    public typealias Output = [RasterImage]
    public typealias ColorSession = NativeGraphicsColorSession
    public typealias DeviceRenderingSession = NativeGraphicsDeviceRenderingSession

    /// Images transmitted by `showpage` so far.
    public private(set) var pages: [RasterImage] = []

    private enum Lifecycle {
      case active
      case finished
      case aborted
    }

    private static let maximumBitmapBytes = 512 * 1_024 * 1_024
    private static let maximumDimension = (1 << 15) - 1

    private var pixelWidth: Int
    private var pixelHeight: Int
    private var descriptor: GraphicsDeviceDescriptor
    private let colorSession: NativeGraphicsColorSession
    private let deviceRenderingSession: NativeGraphicsDeviceRenderingSession
    private var rasterMatrix: GraphicsMatrix
    private var activeDeviceIdentifier: GraphicsDeviceIdentifier?
    private var renderingEnabled = true
    private var surface: OpaquePointer?
    private var canvas: OpaquePointer?
    private var lifecycle = Lifecycle.active
    private var activeImage: (
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      converter: NativeGraphicsColorImageConverter,
      maskOpacities: [Float],
      nextMaskRow: Int
    )?
    private let storage = GraphicsStorageTracker()

    fileprivate init(
      pixelWidth: Int,
      pixelHeight: Int,
      descriptor: GraphicsDeviceDescriptor,
      colorSession: NativeGraphicsColorSession,
      deviceRenderingSession: NativeGraphicsDeviceRenderingSession
    ) throws {
      try Self.validate(pixelWidth: pixelWidth, pixelHeight: pixelHeight, descriptor: descriptor)
      self.pixelWidth = pixelWidth
      self.pixelHeight = pixelHeight
      self.descriptor = descriptor
      self.colorSession = colorSession
      self.deviceRenderingSession = deviceRenderingSession
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
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      guard renderingEnabled else { return }
      guard let canvas else { throw SolidPostScript.Error.ioError }
      switch event.operation {
      case .paint(.erasePage):
        try erasePage(state: event.before, in: canvas)
      case .paint(.fill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before, in: canvas)
      case .paint(.stroke):
        try stroke(event.before.path, state: event.before, in: canvas)
      case .paint(.userPathFill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before, in: canvas)
      case .paint(.userPathStroke):
        try fill(event.before.path, rule: .winding, state: event.before, in: canvas)
      case .paint(.fillRectangles(let paths)):
        try fill(
          GraphicsPath(elements: paths.flatMap(\.elements)),
          rule: .winding,
          state: event.before,
          in: canvas
        )
      case .paint(.strokeRectangles(let paths, let matrix)):
        try strokeRectangles(paths, matrix: matrix, state: event.before, in: canvas)
      case .paint(.shading(let shading)):
        try paintShading(shading, clip: event.before.clip, state: event.before, in: canvas)
      case .paint(.form(let form)):
        try paintForm(form, in: canvas, depth: 0)
      case .paint(.text(let run)):
        try paintText(run, state: event.before, in: canvas, depth: 0)
      case .page(.show), .page(.copy):
        try transmitPage(event, copies: 1)
      default:
        break
      }
    }

    /// Begins one sampled-image transfer.
    public func beginImage(_ event: GraphicsEvent) throws {
      guard lifecycle == .active,
        activeImage == nil,
        case .paint(.image(let descriptor)) = event.operation
      else {
        throw SolidPostScript.Error.ioError
      }
      try storage.beginImage()
      do {
        activeImage = (
          descriptor,
          event.before,
          try colorSession.makeImageConverter(
          for: descriptor,
          deviceRendering: event.before.deviceRendering
          ),
          [],
          0
        )
      } catch {
        storage.abortImage()
        throw error
      }
    }

    /// Consumes one bounded group of complete sampled-image rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard let image = activeImage else { throw SolidPostScript.Error.ioError }
      let components = rows.components.count.addingReportingOverflow(rows.sourceComponents?.count ?? 0)
      guard !components.overflow else { throw GraphicsStorageAccountingError.limitExceeded }
      let bytes = components.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      guard !bytes.overflow else { throw GraphicsStorageAccountingError.limitExceeded }
      try storage.appendImageBytes(bytes.partialValue)
      try image.converter.write(rows)
    }

    /// Consumes one bounded group of complete sampled-image mask rows.
    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
      guard var image = activeImage,
        let (width, height) = maskDimensions(for: image.descriptor),
        width > 0,
        height > 0,
        rows.rowCount > 0,
        rows.startRow == image.nextMaskRow,
        rows.rowCount <= height - image.nextMaskRow,
        rows.rowCount <= Int.max / width,
        rows.opacities.count == rows.rowCount * width
      else { throw SolidPostScript.Error.ioError }
      let bytes = rows.opacities.count.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      guard !bytes.overflow else { throw GraphicsStorageAccountingError.limitExceeded }
      try storage.appendImageBytes(bytes.partialValue)
      image.maskOpacities.append(contentsOf: rows.opacities)
      image.nextMaskRow += rows.rowCount
      activeImage = image
    }

    /// Commits and paints the active sampled image.
    public func endImage() throws {
      guard let image = activeImage, lifecycle == .active else {
        throw SolidPostScript.Error.ioError
      }
      activeImage = nil
      defer { storage.abortImage() }
      let resolved = try image.converter.finish()
      guard renderingEnabled else { return }
      guard let canvas else { throw SolidPostScript.Error.ioError }
      try draw(
        resolved,
        descriptor: image.descriptor,
        state: image.state,
        mask: try rasterMask(descriptor: image.descriptor, opacities: image.maskOpacities),
        in: canvas
      )
    }

    /// Abandons the active sampled image without painting it.
    public func abortImage() {
      activeImage?.converter.abort()
      activeImage = nil
      storage.abortImage()
      storage.abortImage()
    }

    public func installStorageAccounting(_ session: GraphicsStorageAccountingSession) {
      storage.install(session)
    }

    /// Activates page geometry negotiated by the page-device session.
    public func activateDevice(_ device: GraphicsDeviceSnapshot) throws {
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      if device.kind == .null {
        renderingEnabled = false
        return
      }
      renderingEnabled = true
      guard activeDeviceIdentifier != device.identifier else { return }
      let width = Int(device.descriptor.mediaBounds.width.rounded())
      let height = Int(device.descriptor.mediaBounds.height.rounded())
      try Self.validate(pixelWidth: width, pixelHeight: height, descriptor: device.descriptor)
      let page = try Self.makePage(pixelWidth: width, pixelHeight: height)
      releasePage()
      pixelWidth = width
      pixelHeight = height
      descriptor = device.descriptor
      rasterMatrix = Self.makeRasterMatrix(device.descriptor)
      surface = page.surface
      canvas = page.canvas
      activeDeviceIdentifier = device.identifier
    }

    /// Discards the page raster owned by a deactivated device.
    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) {
      if activeDeviceIdentifier == device.identifier {
        releasePage()
        activeDeviceIdentifier = nil
      }
    }

    /// Transmits immutable copies of the current page and starts a fresh surface.
    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      guard lifecycle == .active, copies >= 0 else { throw SolidPostScript.Error.ioError }
      guard renderingEnabled else { return }
      guard let surface else { throw SolidPostScript.Error.ioError }
      if copies > 0 {
        let image = try snapshot(surface)
        pages.append(contentsOf: repeatElement(image, count: copies))
      }
      let next = try Self.makePage(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
      releasePage()
      self.surface = next.surface
      self.canvas = next.canvas
    }

    /// Completes the render and discards the current untransmitted page.
    public func finish() throws -> sending [RasterImage] {
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      lifecycle = .finished
      activeImage?.converter.abort()
      activeImage = nil
      storage.abortImage()
      releasePage()
      let output = pages
      pages.removeAll()
      return output
    }

    /// Abandons the current page and all transmitted output.
    public func abort() {
      guard lifecycle == .active else { return }
      lifecycle = .aborted
      activeImage?.converter.abort()
      activeImage = nil
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
      return try RasterImage(
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        pixelFormat: .rgba8Unorm,
        data: data
      )
    }

    private static func makeRasterMatrix(_ descriptor: GraphicsDeviceDescriptor) -> GraphicsMatrix {
      GraphicsMatrix(
        a: 1,
        b: 0,
        c: 0,
        d: -1,
        tx: -descriptor.mediaBounds.x,
        ty: descriptor.mediaBounds.maxY
      )
    }

    private func erasePage(state: GraphicsStateSnapshot, in canvas: OpaquePointer) throws {
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try setMatrix(rasterMatrix, in: canvas)
      try setPaint(state.paint, state: state, in: canvas)
      try addRect(descriptor.mediaBounds, to: canvas)
      plutovg_canvas_fill(canvas)
    }

    private func fill(
      _ path: GraphicsPath,
      rule: GraphicsFillRule,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      if case .pattern(let pattern) = state.paint {
        try fillPattern(pattern, through: path, rule: rule, state: state, in: canvas, depth: 0)
        return
      }
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try replay(state.clip, in: canvas)
      try setMatrix(rasterMatrix, in: canvas)
      try add(path, to: canvas)
      setFillRule(rule, in: canvas)
      try setPaint(state.paint, state: state, in: canvas)
      plutovg_canvas_fill(canvas)
    }

    private func stroke(
      _ path: GraphicsPath,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      try stroke(path, matrix: state.matrix, state: state, in: canvas)
    }

    private func stroke(
      _ path: GraphicsPath,
      matrix: GraphicsMatrix,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      if case .pattern = state.paint {
        let outline = try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
        try fill(outline, rule: .winding, state: state, in: canvas)
        return
      }
      if state.strokeAdjustment {
        let outline = try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
        try fill(outline, rule: .winding, state: state, in: canvas)
        return
      }
      guard let inverse = matrix.inverted else { return }
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try replay(state.clip, in: canvas)
      try setMatrix(matrix.concatenated(with: rasterMatrix), in: canvas)
      try add(path.transformed(by: inverse), to: canvas)
      try setPaint(state.paint, state: state, in: canvas)
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

    private func fillPattern(
      _ paint: GraphicsPatternPaint,
      through path: GraphicsPath,
      rule: GraphicsFillRule,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer,
      depth: Int
    ) throws {
      guard depth < 16 else { throw SolidPostScript.Error.ioError }
      switch paint {
      case .empty:
        return
      case .shading(let shading):
        try paintShading(shading, clip: nil, state: state, in: canvas)
      case .tiling(let pattern, let underlying):
        plutovg_canvas_save(canvas)
        defer { plutovg_canvas_restore(canvas) }
        try replay(state.clip, in: canvas)
        try setMatrix(rasterMatrix, in: canvas)
        try add(path, to: canvas)
        setFillRule(rule, in: canvas)
        plutovg_canvas_clip(canvas)
        for translation in try tileTranslations(for: pattern) {
          for effect in pattern.displayList.effects {
            try replayPatternEffect(
              effect,
              translation: translation,
              underlying: underlying,
              in: canvas,
              depth: depth + 1
            )
          }
        }
      }
    }

    private func paintForm(_ form: GraphicsForm, in canvas: OpaquePointer, depth: Int) throws {
      guard depth < 16 else { throw SolidPostScript.Error.ioError }
      for effect in form.displayList.effects {
        try replayFormEffect(effect, in: canvas, depth: depth + 1)
      }
    }

    private func replayFormEffect(_ effect: GraphicsEffect, in canvas: OpaquePointer, depth: Int) throws {
      switch effect {
      case .markedContent:
        break
      case .fill(let path, let rule, let state), .userPathFill(let path, let rule, let state):
        try fill(path, rule: rule, state: state, in: canvas)
      case .stroke(let path, let state):
        try stroke(path, state: state, in: canvas)
      case .userPathStroke(let outline, let state):
        try fill(outline, rule: .winding, state: state, in: canvas)
      case .erase(let state):
        try erasePage(state: state, in: canvas)
      case .fillRectangles(let paths, let state):
        try fill(
          GraphicsPath(elements: paths.flatMap(\.elements)),
          rule: .winding,
          state: state,
          in: canvas
        )
      case .strokeRectangles(let paths, let matrix, let state):
        try strokeRectangles(paths, matrix: matrix, state: state, in: canvas)
      case .image(let image, let state):
        let converter = try colorSession.makeImageConverter(
          for: image.descriptor,
          deviceRendering: state.deviceRendering
        )
        do {
          try converter.write(GraphicsImageRows(
            startRow: 0,
            rowCount: image.completedRowCount,
            components: image.components,
            sourceComponents: image.sourceComponents
          ))
          try draw(
            converter.finish(),
            descriptor: image.descriptor,
            state: state,
            mask: try rasterMask(descriptor: image.descriptor, opacities: image.mask?.opacities ?? []),
            in: canvas
          )
        } catch {
          converter.abort()
          throw error
        }
      case .shading(let shading, let state):
        try paintShading(shading, clip: state.clip, state: state, in: canvas)
      case .form(let nested, _):
        try paintForm(nested, in: canvas, depth: depth)
      case .text(let run, let state):
        try paintText(run, state: state, in: canvas, depth: depth)
      }
    }

    private func paintText(
      _ run: GraphicsGlyphRun,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer,
      depth: Int
    ) throws {
      guard depth < 16 else { throw SolidPostScript.Error.ioError }
      let fillState = run.style.map { state.replacingColor(with: $0.fill) } ?? state
      let strokeState = run.style.map { state.replacingColor(with: $0.stroke) } ?? state
      for placement in run.glyphs {
        switch placement.glyph.program {
        case .outline(let path):
          let outline = path.transformed(by: placement.transform)
          if run.renderingMode.fills {
            try fill(outline, rule: .winding, state: fillState, in: canvas)
          }
          if run.renderingMode.strokes {
            try stroke(outline, matrix: state.matrix, state: strokeState, in: canvas)
          }
        case .displayList(let list):
          guard run.renderingMode != .invisible else { continue }
          for effect in list.effects { try replayFormEffect(effect, in: canvas, depth: depth + 1) }
        case .bitmap, .empty, .missing:
          break
        }
      }
    }

    private func replayPatternEffect(
      _ effect: GraphicsEffect,
      translation: GraphicsMatrix,
      underlying: GraphicsPaint?,
      in canvas: OpaquePointer,
      depth: Int
    ) throws {
      if case .text(let run, let textState) = effect {
        for placement in run.glyphs {
          switch placement.glyph.program {
          case .outline(let path):
            try replayPatternEffect(
              .fill(path: path.transformed(by: placement.transform), rule: .winding, state: textState),
              translation: translation,
              underlying: underlying,
              in: canvas,
              depth: depth + 1
            )
          case .displayList(let list):
            for nested in list.effects {
              try replayPatternEffect(
                nested,
                translation: translation,
                underlying: underlying,
                in: canvas,
                depth: depth + 1
              )
            }
          case .bitmap, .empty, .missing:
            break
          }
        }
        return
      }
      if case .image(let image, let imageState) = effect {
        let translatedConstraints = imageState.clip.constraints.map {
          GraphicsClipConstraint(path: $0.path.transformed(by: translation), rule: $0.rule)
        }
        let kind: GraphicsImageKind
        switch image.descriptor.kind {
        case .color(let space): kind = .color(space)
        case .mask(let paint): kind = .mask(underlying ?? paint)
        }
        let descriptor = GraphicsImageDescriptor(
          width: image.descriptor.width,
          height: image.descriptor.height,
          kind: kind,
          sourceColorSpace: image.descriptor.sourceColorSpace,
          imageToDevice: image.descriptor.imageToDevice.concatenated(with: translation),
          interpolate: image.descriptor.interpolate,
          mask: image.descriptor.mask?.transformed(by: translation)
        )
        let converter = try colorSession.makeImageConverter(
          for: descriptor,
          deviceRendering: imageState.deviceRendering
        )
        do {
          try converter.write(GraphicsImageRows(
            startRow: 0,
            rowCount: image.completedRowCount,
            components: image.components,
            sourceComponents: image.sourceComponents
          ))
          let state = GraphicsStateSnapshot(
            matrix: imageState.matrix,
            path: imageState.path,
            clip: GraphicsClip(
              imageableBounds: imageState.clip.imageableBounds,
              constraints: translatedConstraints
            ),
            paint: imageState.paint,
            colorSpace: imageState.colorSpace,
            colorComponents: imageState.colorComponents,
            overprint: imageState.overprint,
            lineWidth: imageState.lineWidth,
            lineCap: imageState.lineCap,
            lineJoin: imageState.lineJoin,
            miterLimit: imageState.miterLimit,
            dash: imageState.dash,
            flatness: imageState.flatness,
            strokeAdjustment: imageState.strokeAdjustment,
            smoothness: imageState.smoothness,
            pathBoundingBox: imageState.pathBoundingBox,
            device: imageState.device,
            deviceRendering: imageState.deviceRendering
          )
          try draw(
            converter.finish(),
            descriptor: descriptor,
            state: state,
            mask: try rasterMask(descriptor: descriptor, opacities: image.mask?.opacities ?? []),
            in: canvas
          )
        } catch {
          converter.abort()
          throw error
        }
        return
      }
      let path: GraphicsPath
      let rule: GraphicsFillRule
      let state: GraphicsStateSnapshot
      switch effect {
      case .markedContent:
        return
      case .form(let form, _):
        guard depth < 16 else { throw SolidPostScript.Error.ioError }
        for nested in form.displayList.effects {
          try replayPatternEffect(
            nested,
            translation: translation,
            underlying: underlying,
            in: canvas,
            depth: depth + 1
          )
        }
        return
      case .fill(let value, let valueRule, let valueState),
           .userPathFill(let value, let valueRule, let valueState):
        path = value.transformed(by: translation)
        rule = valueRule
        state = valueState
      case .stroke(let value, let valueState):
        path = try GraphicsPathGeometry.strokeOutline(path: value, state: valueState).transformed(by: translation)
        rule = .winding
        state = valueState
      case .userPathStroke(let value, let valueState):
        path = value.transformed(by: translation)
        rule = .winding
        state = valueState
      case .fillRectangles(let paths, let valueState):
        path = GraphicsPath(elements: paths.flatMap(\.elements)).transformed(by: translation)
        rule = .winding
        state = valueState
      case .strokeRectangles(let paths, let matrix, let valueState):
        let source = GraphicsPath(elements: paths.flatMap(\.elements))
        path = try GraphicsPathGeometry.strokeOutline(
          path: source,
          state: valueState,
          matrix: matrix?.concatenated(with: valueState.matrix) ?? valueState.matrix
        ).transformed(by: translation)
        rule = .winding
        state = valueState
      case .erase(let valueState):
        path = GraphicsPath.rectangle(descriptor.mediaBounds).transformed(by: translation)
        rule = .winding
        state = valueState
      case .image:
        preconditionFailure("Image effects are handled before vector effects")
      case .shading(let shading, let shadingState):
        try paintShading(
          translatedShading(shading, by: translation),
          clip: GraphicsClip(
            imageableBounds: shadingState.clip.imageableBounds,
            constraints: shadingState.clip.constraints.map {
              .init(path: $0.path.transformed(by: translation), rule: $0.rule)
            }
          ),
          state: shadingState,
          in: canvas
        )
        return
      case .text:
        preconditionFailure("Text effects are handled before vector replay")
      }

      let selectedPaint = underlying ?? state.paint
      if case .pattern(let nested) = selectedPaint {
        try fillPattern(nested, through: path, rule: rule, state: state, in: canvas, depth: depth)
        return
      }
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try setMatrix(rasterMatrix, in: canvas)
      for constraint in state.clip.constraints {
        try add(constraint.path.transformed(by: translation), to: canvas)
        setFillRule(constraint.rule, in: canvas)
        plutovg_canvas_clip(canvas)
      }
      try add(path, to: canvas)
      setFillRule(rule, in: canvas)
      try setPaint(selectedPaint, state: state, in: canvas)
      plutovg_canvas_fill(canvas)
    }

    private func tileTranslations(for pattern: GraphicsTilingPattern) throws -> [GraphicsMatrix] {
      let origin = pattern.matrix.transform(GraphicsPoint(x: 0, y: 0))
      let requestedXStep = pattern.matrix.transformDistance(GraphicsPoint(x: pattern.xStep, y: 0))
      let requestedYStep = pattern.matrix.transformDistance(GraphicsPoint(x: 0, y: pattern.yStep))
      let xStep = pattern.tilingType == 2 ? requestedXStep : adjustedLatticeStep(requestedXStep)
      let yStep = pattern.tilingType == 2 ? requestedYStep : adjustedLatticeStep(requestedYStep)
      guard let inverse = GraphicsMatrix(
        a: xStep.x, b: xStep.y, c: yStep.x, d: yStep.y, tx: origin.x, ty: origin.y
      ).inverted else { throw SolidPostScript.Error.ioError }
      let media = descriptor.mediaBounds
      let coordinates = [
        GraphicsPoint(x: media.x, y: media.y), GraphicsPoint(x: media.maxX, y: media.y),
        GraphicsPoint(x: media.maxX, y: media.maxY), GraphicsPoint(x: media.x, y: media.maxY),
      ].map(inverse.transform)
      let minX = Int((coordinates.map(\.x).min()! - 1).rounded(.down))
      let maxX = Int((coordinates.map(\.x).max()! + 1).rounded(.up))
      let minY = Int((coordinates.map(\.y).min()! - 1).rounded(.down))
      let maxY = Int((coordinates.map(\.y).max()! + 1).rounded(.up))
      let columns = maxX - minX + 1
      let rows = maxY - minY + 1
      guard columns > 0, rows > 0, rows <= 1_000_000 / columns else {
        throw SolidPostScript.Error.ioError
      }
      var result: [GraphicsMatrix] = []
      result.reserveCapacity(columns * rows)
      for row in minY...maxY {
        for column in minX...maxX {
          let tx = Double(column) * xStep.x + Double(row) * yStep.x
          let ty = Double(column) * xStep.y + Double(row) * yStep.y
          result.append(GraphicsMatrix(
            a: 1, b: 0, c: 0, d: 1,
            tx: pattern.tilingType == 2 ? tx.rounded() : tx,
            ty: pattern.tilingType == 2 ? ty.rounded() : ty
          ))
        }
      }
      return result
    }

    private func adjustedLatticeStep(_ value: GraphicsPoint) -> GraphicsPoint {
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

    private func fillRectangles(
      _ paths: [GraphicsPath],
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try replay(state.clip, in: canvas)
      try setMatrix(rasterMatrix, in: canvas)
      try add(GraphicsPath(elements: paths.flatMap(\.elements)), to: canvas)
      try setPaint(state.paint, state: state, in: canvas)
      plutovg_canvas_fill(canvas)
    }

    private func paintShading(
      _ shading: GraphicsShading,
      clip: GraphicsClip?,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      let paints = shading.mesh.triangles.flatMap {
        [$0.first.paint, $0.second.paint, $0.third.paint]
      }
      let resolved = try colorSession.resolve(paints, deviceRendering: state.deviceRendering)
      var offset = 0
      let triangles = try shading.mesh.triangles.map { triangle -> RasterGradientTriangle in
        defer { offset += 3 }
        guard case .solid(let first) = resolved[offset],
          case .solid(let second) = resolved[offset + 1],
          case .solid(let third) = resolved[offset + 2]
        else { throw SolidPostScript.Error.ioError }
        return .init(
          first: .init(position: rasterMatrix.transform(triangle.first.position).raster, color: first),
          second: .init(position: rasterMatrix.transform(triangle.second.position).raster, color: second),
          third: .init(position: rasterMatrix.transform(triangle.third.position).raster, color: third)
        )
      }
      var fallback = try RasterCanvas(
        width: pixelWidth,
        height: pixelHeight,
        background: RasterColor(red: 0, green: 0, blue: 0, alpha: 0)
      )
      try fallback.paint(RasterGradientMesh(triangles: triangles))
      let image = try fallback.finish()
      let imageDescriptor = GraphicsImageDescriptor(
        width: pixelWidth,
        height: pixelHeight,
        kind: .color(.deviceRGB),
        imageToDevice: GraphicsMatrix(
          a: 1, b: 0, c: 0, d: -1,
          tx: descriptor.mediaBounds.x,
          ty: descriptor.mediaBounds.maxY
        ),
        interpolate: true
      )
      let shadingConstraints = shading.clipPath.map {
        [GraphicsClipConstraint(path: $0, rule: .winding)]
      } ?? []
      let baseClip = clip ?? GraphicsClip(imageableBounds: descriptor.imageableBounds)
      let state = GraphicsStateSnapshot(
        matrix: .identity,
        path: .init(),
        clip: GraphicsClip(
          imageableBounds: baseClip.imageableBounds,
          constraints: baseClip.constraints + shadingConstraints
        ),
        paint: .deviceGray(0),
        lineWidth: 1,
        lineCap: .butt,
        lineJoin: .miter,
        miterLimit: 10,
        dash: .init(),
        device: state.device,
        deviceRendering: state.deviceRendering
      )
      if let background = shading.background {
        plutovg_canvas_save(canvas)
        defer { plutovg_canvas_restore(canvas) }
        try replay(state.clip, in: canvas)
        try setMatrix(rasterMatrix, in: canvas)
        try setPaint(background, state: state, in: canvas)
        try addRect(descriptor.mediaBounds, to: canvas)
        plutovg_canvas_fill(canvas)
      }
      try draw(image, descriptor: imageDescriptor, state: state, in: canvas)
    }

    private func translatedShading(_ shading: GraphicsShading, by matrix: GraphicsMatrix) -> GraphicsShading {
      GraphicsShading(
        type: shading.type,
        colorSpace: shading.colorSpace,
        background: shading.background,
        bounds: shading.bounds,
        clipPath: shading.clipPath?.transformed(by: matrix),
        antialias: shading.antialias,
        geometry: shading.geometry,
        mesh: .init(triangles: shading.mesh.triangles.map { triangle in
          .init(
            first: .init(position: matrix.transform(triangle.first.position), paint: triangle.first.paint),
            second: .init(position: matrix.transform(triangle.second.position), paint: triangle.second.paint),
            third: .init(position: matrix.transform(triangle.third.position), paint: triangle.third.paint)
          )
        })
      )
    }

    private func strokeRectangles(
      _ paths: [GraphicsPath],
      matrix: GraphicsMatrix?,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      let effectiveMatrix = matrix?.concatenated(with: state.matrix) ?? state.matrix
      try stroke(
        GraphicsPath(elements: paths.flatMap(\.elements)),
        matrix: effectiveMatrix,
        state: state,
        in: canvas
      )
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

    private func draw(
      _ image: RasterImage,
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      mask: RasterMask? = nil,
      in canvas: OpaquePointer
    ) throws {
      if let mask {
        if let masked = try alignedMaskedImage(image, mask: mask, descriptor: descriptor) {
          try draw(masked, descriptor: descriptor, state: state, in: canvas)
          return
        }
        try drawPortableMaskedImage(image, mask: mask, descriptor: descriptor, state: state, in: canvas)
        return
      }
      let renderedHeight = image.height
      guard descriptor.width > 0,
        renderedHeight > 0,
        renderedHeight <= descriptor.height,
        image.width == descriptor.width
      else { return }
      var data = image.data
      plutovg_canvas_save(canvas)
      defer { plutovg_canvas_restore(canvas) }
      try replay(state.clip, in: canvas)
      try setMatrix(rasterMatrix, in: canvas)
      let imagePath = try imageBoundary(descriptor, renderedHeight: renderedHeight)
      try add(imagePath, to: canvas)
      var textureMatrix = try plutoMatrix(descriptor.imageToDevice)
      try data.withUnsafeMutableBytes { bytes in
        guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          throw SolidPostScript.Error.ioError
        }
        plutovg_convert_rgba_to_argb(
          base,
          base,
          Int32(descriptor.width),
          Int32(renderedHeight),
          Int32(descriptor.width * 4)
        )
        guard let imageSurface = plutovg_surface_create_for_data(
          base,
          Int32(descriptor.width),
          Int32(renderedHeight),
          Int32(descriptor.width * 4)
        ) else {
          throw SolidPostScript.Error.ioError
        }
        defer { plutovg_surface_destroy(imageSurface) }
        plutovg_canvas_set_texture(
          canvas,
          imageSurface,
          PLUTOVG_TEXTURE_TYPE_PLAIN,
          1,
          &textureMatrix
        )
        plutovg_canvas_fill(canvas)
        plutovg_canvas_set_rgb(canvas, 0, 0, 0)
      }
    }

    private func alignedMaskedImage(
      _ image: RasterImage,
      mask: RasterMask,
      descriptor: GraphicsImageDescriptor
    ) throws -> RasterImage? {
      let maskTransform: GraphicsMatrix
      let maskInterpolation: Bool
      switch descriptor.mask {
      case .explicit(let width, let height, let transform, let interpolate):
        guard width == descriptor.width, height == descriptor.height else { return nil }
        maskTransform = transform
        maskInterpolation = interpolate
      case .colorKey:
        maskTransform = descriptor.imageToDevice
        maskInterpolation = descriptor.interpolate
      case nil:
        return nil
      }
      guard mask.width == descriptor.width,
        mask.height >= image.height,
        maskTransform == descriptor.imageToDevice,
        maskInterpolation == descriptor.interpolate
      else { return nil }

      var data = image.data
      for row in 0..<image.height {
        for column in 0..<image.width {
          let opacity = UInt16(mask.data[row * mask.bytesPerRow + column])
          let offset = row * image.bytesPerRow + column * 4
          if image.pixelFormat == .rgba8UnormPremultiplied {
            data[offset] = UInt8((UInt16(data[offset]) * opacity + 127) / 255)
            data[offset + 1] = UInt8((UInt16(data[offset + 1]) * opacity + 127) / 255)
            data[offset + 2] = UInt8((UInt16(data[offset + 2]) * opacity + 127) / 255)
          }
          data[offset + 3] = UInt8((UInt16(data[offset + 3]) * opacity + 127) / 255)
        }
      }
      do {
        return try RasterImage(
          width: image.width,
          height: image.height,
          bytesPerRow: image.bytesPerRow,
          pixelFormat: image.pixelFormat,
          data: data
        )
      } catch {
        throw SolidPostScript.Error.ioError
      }
    }

    private func drawPortableMaskedImage(
      _ image: RasterImage,
      mask: RasterMask,
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      do {
        var overlay = try RasterCanvas(width: pixelWidth, height: pixelHeight)
        try overlay.setClip(RasterClip(
          imageableBounds: transformedBounds(state.clip.imageableBounds, by: rasterMatrix).raster,
          constraints: state.clip.constraints.map {
            RasterClipConstraint(
              path: $0.path.transformed(by: rasterMatrix).rasterPath,
              rule: $0.rule == .evenOdd ? .evenOdd : .winding
            )
          }
        ))
        let maskTransform: GraphicsMatrix
        let maskInterpolation: RasterInterpolation
        if case .explicit(_, _, let explicitTransform, let interpolate) = descriptor.mask {
          maskTransform = explicitTransform
          maskInterpolation = interpolate ? .linear : .nearest
        } else {
          maskTransform = descriptor.imageToDevice
          maskInterpolation = descriptor.interpolate ? .linear : .nearest
        }
        try overlay.draw(
          image,
          transform: descriptor.imageToDevice.concatenated(with: rasterMatrix).raster,
          interpolation: descriptor.interpolate ? .linear : .nearest,
          mask: mask,
          maskTransform: maskTransform.concatenated(with: rasterMatrix).raster,
          maskInterpolation: maskInterpolation
        )
        let raster = try overlay.finish(pixelFormat: .rgba8UnormPremultiplied)
        guard let inverseRaster = rasterMatrix.inverted else { throw SolidPostScript.Error.ioError }
        try draw(
          raster,
          descriptor: GraphicsImageDescriptor(
            width: pixelWidth,
            height: pixelHeight,
            kind: .color(.deviceRGB),
            imageToDevice: inverseRaster
          ),
          state: state,
          in: canvas
        )
      } catch {
        if error is SolidPostScript.Error { throw error }
        throw SolidPostScript.Error.ioError
      }
    }

    private func maskDimensions(for descriptor: GraphicsImageDescriptor) -> (width: Int, height: Int)? {
      switch descriptor.mask {
      case .explicit(let width, let height, _, _): (width, height)
      case .colorKey: (descriptor.width, descriptor.height)
      case nil: nil
      }
    }

    private func rasterMask(descriptor: GraphicsImageDescriptor, opacities: [Float]) throws -> RasterMask? {
      guard let (width, height) = maskDimensions(for: descriptor) else { return nil }
      guard width > 0,
        height > 0,
        width <= Int.max / height,
        width * height <= RasterLimits.default.maximumSurfaceBytes,
        opacities.count <= width * height
      else { throw SolidPostScript.Error.ioError }
      var data = Data(repeating: 0, count: width * height)
      for index in opacities.indices {
        data[index] = UInt8((min(1, max(0, opacities[index])) * 255).rounded())
      }
      do {
        return try RasterMask(width: width, height: height, bytesPerRow: width, data: data)
      } catch {
        throw SolidPostScript.Error.ioError
      }
    }

    private func transformedBounds(_ rect: GraphicsRect, by matrix: GraphicsMatrix) -> GraphicsRect {
      let points = [
        GraphicsPoint(x: rect.x, y: rect.y),
        GraphicsPoint(x: rect.maxX, y: rect.y),
        GraphicsPoint(x: rect.maxX, y: rect.maxY),
        GraphicsPoint(x: rect.x, y: rect.maxY),
      ].map(matrix.transform)
      let minX = points.map(\.x).min()!
      let maxX = points.map(\.x).max()!
      let minY = points.map(\.y).min()!
      let maxY = points.map(\.y).max()!
      return GraphicsRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func imageBoundary(
      _ descriptor: GraphicsImageDescriptor,
      renderedHeight: Int
    ) throws -> GraphicsPath {
      let matrix = descriptor.imageToDevice
      let points = [
        GraphicsPoint(x: 0, y: 0),
        GraphicsPoint(x: Double(descriptor.width), y: 0),
        GraphicsPoint(x: Double(descriptor.width), y: Double(renderedHeight)),
        GraphicsPoint(x: 0, y: Double(renderedHeight)),
      ].map(matrix.transform)
      return GraphicsPath(elements: [
        .move(to: points[0]),
        .line(to: points[1]),
        .line(to: points[2]),
        .line(to: points[3]),
        .close,
      ])
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

    private func setPaint(
      _ paint: GraphicsPaint,
      state: GraphicsStateSnapshot,
      in canvas: OpaquePointer
    ) throws {
      let resolved = try colorSession.resolve(paint, deviceRendering: state.deviceRendering)
      guard case .solid(let color) = resolved else { throw SolidPostScript.Error.ioError }
      plutovg_canvas_set_rgb(canvas, try float(color.red), try float(color.green), try float(color.blue))
    }

    private func setFillRule(_ rule: GraphicsFillRule, in canvas: OpaquePointer) {
      plutovg_canvas_set_fill_rule(canvas, rule.plutoVG)
    }

    private func setMatrix(_ matrix: GraphicsMatrix, in canvas: OpaquePointer) throws {
      var native = try plutoMatrix(matrix)
      plutovg_canvas_set_matrix(canvas, &native)
    }

    private func plutoMatrix(_ matrix: GraphicsMatrix) throws -> plutovg_matrix_t {
      plutovg_matrix_t(
        a: try float(matrix.a),
        b: try float(matrix.b),
        c: try float(matrix.c),
        d: try float(matrix.d),
        e: try float(matrix.tx),
        f: try float(matrix.ty)
      )
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
  /// The native Swift color engine used as PlutoVG's conversion frontend.
  public let colorEngine: NativeGraphicsColorEngine
  /// The native rendering engine used when PlutoVG cannot reproduce device controls.
  public let deviceRenderingEngine = NativeGraphicsDeviceRenderingEngine()
  /// The virtual page-device provider used by this target.
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider

  /// Creates an RGBA bitmap target with explicit pixel geometry and resolution.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    resolution: Double = 72,
    imageableBounds: GraphicsRect? = nil,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.colorEngine = NativeGraphicsColorEngine()
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(mode: pageDeviceMode)
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
    deviceDescriptor: GraphicsDeviceDescriptor,
    pageDeviceMode: GraphicsPageDeviceMode = .adaptive
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.deviceDescriptor = deviceDescriptor
    self.colorEngine = NativeGraphicsColorEngine(destinationProfile: deviceDescriptor.colorDevice.destinationProfile)
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(mode: pageDeviceMode)
  }

  /// Creates a renderer dedicated to one render operation.
  public func makeRenderer() throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorEngine.makeSession(for: deviceDescriptor),
      deviceRenderingSession: deviceRenderingEngine.makeSession(for: deviceDescriptor)
    )
  }

  /// Creates a renderer with color conversion state prepared for this render.
  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession
  ) throws -> sending Renderer {
    try makeRenderer(
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingEngine.makeSession(for: deviceDescriptor)
    )
  }

  /// Creates a renderer with prepared color and device-rendering state.
  public func makeRenderer(
    colorSession: sending NativeGraphicsColorSession,
    deviceRenderingSession: sending NativeGraphicsDeviceRenderingSession
  ) throws -> sending Renderer {
    try Renderer(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      descriptor: deviceDescriptor,
      colorSession: colorSession,
      deviceRenderingSession: deviceRenderingSession
    )
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
  var rasterPath: RasterPath {
    RasterPath(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: point.raster)
      case .line(let point): .line(to: point.raster)
      case .curve(let control1, let control2, let end):
        .cubic(control1: control1.raster, control2: control2.raster, end: end.raster)
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

private extension GraphicsPoint {
  var raster: RasterPoint { RasterPoint(x: x, y: y) }
}

private extension GraphicsMatrix {
  var raster: RasterAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

private extension GraphicsRect {
  var raster: RasterRect { .init(x: x, y: y, width: width, height: height) }
}
