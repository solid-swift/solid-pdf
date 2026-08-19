import Foundation
import SolidPostScript
import SolidRaster

/// A portable PostScript raster target parameterized by a compatible color engine.
public struct ColorManagedRasterImageTarget<ColorEngine: GraphicsColorEngine>: GraphicsTarget, Sendable
where
  ColorEngine.Session.ResolvedPaint == RasterPaint,
  ColorEngine.Session.ImageConverter.ResolvedImage == RasterImage
{
  public typealias PageOutput = RasterImage
  public typealias Output = [RasterImage]

  /// A renderer dedicated to one native raster job.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = RasterImage
    public typealias Output = [RasterImage]
    public typealias ColorSession = ColorEngine.Session

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
    private let colorSession: ColorEngine.Session
    private let rasterMatrix: GraphicsMatrix
    private var canvas: RasterCanvas?
    private var lifecycle = Lifecycle.active
    private var activeImage: (
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      converter: ColorEngine.Session.ImageConverter
    )?
    private var cachedGraphicsClip: GraphicsClip?
    private var cachedRasterClip: RasterClip?

    fileprivate init(
      pixelWidth: Int,
      pixelHeight: Int,
      descriptor: GraphicsDeviceDescriptor,
      colorSession: ColorEngine.Session
    ) throws {
      try Self.validate(pixelWidth: pixelWidth, pixelHeight: pixelHeight, descriptor: descriptor)
      self.pixelWidth = pixelWidth
      self.pixelHeight = pixelHeight
      self.descriptor = descriptor
      self.colorSession = colorSession
      rasterMatrix = GraphicsMatrix(
        a: 1,
        b: 0,
        c: 0,
        d: -1,
        tx: -descriptor.mediaBounds.x,
        ty: descriptor.mediaBounds.maxY
      )
      canvas = nil
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
      case .paint(.userPathFill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before)
      case .paint(.userPathStroke):
        try fill(event.before.path, rule: .winding, state: event.before)
      case .paint(.fillRectangles(let paths)):
        try fill(GraphicsPath(elements: paths.flatMap(\.elements)), rule: .winding, state: event.before)
      case .paint(.strokeRectangles(let paths, let matrix)):
        let effectiveMatrix = matrix?.concatenated(with: event.before.matrix) ?? event.before.matrix
        try stroke(
          GraphicsPath(elements: paths.flatMap(\.elements)),
          matrix: effectiveMatrix,
          state: event.before
        )
      case .paint(.shading(let shading)):
        try paintShading(shading, clip: event.before.clip)
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
      activeImage = (
        descriptor,
        event.before,
        try colorSession.makeImageConverter(for: descriptor)
      )
    }

    /// Receives complete sampled-image rows in order.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard let image = activeImage else { throw SolidPostScript.Error.ioError }
      try image.converter.write(rows)
    }

    /// Validates and paints the active sampled image.
    public func endImage() throws {
      guard let image = activeImage, lifecycle == .active else { throw SolidPostScript.Error.ioError }
      activeImage = nil
      try draw(
        image.converter.finish(),
        descriptor: image.descriptor,
        state: image.state
      )
    }

    /// Abandons the active sampled image.
    public func abortImage() {
      activeImage?.converter.abort()
      activeImage = nil
    }

    /// Completes the render and discards its untransmitted page.
    public func finish() throws -> sending [RasterImage] {
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      lifecycle = .finished
      activeImage?.converter.abort()
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
      activeImage?.converter.abort()
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
      guard lifecycle == .active else {
        throw SolidPostScript.Error.ioError
      }
      var current = try takeCanvas()
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
      if case .pattern(let pattern) = state.paint {
        try paintPattern(pattern, through: path, rule: rule, clip: state.clip, depth: 0)
        return
      }
      let transformed = path.transformed(by: rasterMatrix).rasterPath
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(state.clip))
        try canvas.fill(transformed, rule: rule.raster, paint: try colorSession.resolve(state.paint))
      }
    }

    private func stroke(
      _ path: GraphicsPath,
      matrix: GraphicsMatrix,
      state: GraphicsStateSnapshot
    ) throws {
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
          paint: try colorSession.resolve(state.paint),
          transform: strokeTransform
        )
      }
    }

    private func paintPattern(
      _ paint: GraphicsPatternPaint,
      through path: GraphicsPath,
      rule: GraphicsFillRule,
      clip: GraphicsClip,
      depth: Int
    ) throws {
      guard depth < 16 else { throw SolidPostScript.Error.ioError }
      switch paint {
      case .empty:
        return
      case .shading(let shading):
        let combinedClip = GraphicsClip(
          imageableBounds: clip.imageableBounds,
          constraints: clip.constraints + [GraphicsClipConstraint(path: path, rule: rule)]
        )
        try paintShading(shading, clip: combinedClip)
      case .tiling(let pattern, let underlying):
        let translations = try tileTranslations(for: pattern)
        guard translations.count <= 1_000_000 else { throw SolidPostScript.Error.ioError }
        for translation in translations {
          for effect in pattern.displayList.effects {
            try replay(
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

    private func replay(
      _ effect: GraphicsEffect,
      translatedBy translation: GraphicsMatrix,
      underlying: GraphicsPaint?,
      through paintedPath: GraphicsPath,
      rule paintedRule: GraphicsFillRule,
      clip: GraphicsClip,
      depth: Int
    ) throws {
      if case .image(let image, let imageState) = effect {
        let translatedConstraints = imageState.clip.constraints.map {
          GraphicsClipConstraint(path: $0.path.transformed(by: translation), rule: $0.rule)
        }
        let combinedClip = GraphicsClip(
          imageableBounds: clip.imageableBounds,
          constraints: clip.constraints
            + [GraphicsClipConstraint(path: paintedPath, rule: paintedRule)]
            + translatedConstraints
        )
        let kind: GraphicsImageKind
        switch image.descriptor.kind {
        case .color(let space):
          kind = .color(space)
        case .mask(let paint):
          kind = .mask(underlying ?? paint)
        }
        let descriptor = GraphicsImageDescriptor(
          width: image.descriptor.width,
          height: image.descriptor.height,
          kind: kind,
          sourceColorSpace: image.descriptor.sourceColorSpace,
          imageToDevice: image.descriptor.imageToDevice.concatenated(with: translation),
          interpolate: image.descriptor.interpolate
        )
        let converter = try colorSession.makeImageConverter(for: descriptor)
        do {
          try converter.write(GraphicsImageRows(
            startRow: 0,
            rowCount: descriptor.height,
            components: image.components,
            sourceComponents: image.sourceComponents
          ))
          var state = imageState
          state = GraphicsStateSnapshot(
            matrix: state.matrix,
            path: state.path,
            clip: combinedClip,
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
            pathBoundingBox: state.pathBoundingBox
          )
          try draw(converter.finish(), descriptor: descriptor, state: state)
        } catch {
          converter.abort()
          throw error
        }
        return
      }
      let effectPath: GraphicsPath
      let effectRule: GraphicsFillRule
      let effectState: GraphicsStateSnapshot
      switch effect {
      case .form:
        return
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
      case .fillRectangles(let paths, let state):
        effectPath = GraphicsPath(elements: paths.flatMap(\.elements)).transformed(by: translation)
        effectRule = .winding
        effectState = state
      case .strokeRectangles(let paths, let matrix, let state):
        let combined = GraphicsPath(elements: paths.flatMap(\.elements))
        let effectiveMatrix = matrix?.concatenated(with: state.matrix) ?? state.matrix
        effectPath = try GraphicsPathGeometry.strokeOutline(
          path: combined,
          state: state,
          matrix: effectiveMatrix
        ).transformed(by: translation)
        effectRule = .winding
        effectState = state
      case .erase(let state):
        effectPath = GraphicsPath.rectangle(descriptor.mediaBounds).transformed(by: translation)
        effectRule = .winding
        effectState = state
      case .image:
        preconditionFailure("Image effects are handled before vector effects")
      case .shading(let shading, let shadingState):
        let translatedConstraints = shadingState.clip.constraints.map {
          GraphicsClipConstraint(path: $0.path.transformed(by: translation), rule: $0.rule)
        }
        let translatedMesh = GraphicsShading(
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
          translatedMesh,
          clip: GraphicsClip(
            imageableBounds: clip.imageableBounds,
            constraints: clip.constraints
              + [GraphicsClipConstraint(path: paintedPath, rule: paintedRule)]
              + translatedConstraints
          )
        )
        return
      }

      let translatedConstraints = effectState.clip.constraints.map {
        GraphicsClipConstraint(path: $0.path.transformed(by: translation), rule: $0.rule)
      }
      let combinedClip = GraphicsClip(
        imageableBounds: clip.imageableBounds,
        constraints: clip.constraints
          + [GraphicsClipConstraint(path: paintedPath, rule: paintedRule)]
          + translatedConstraints
      )
      let effectPaint = underlying ?? effectState.paint
      if case .pattern(let nested) = effectPaint {
        try paintPattern(nested, through: effectPath, rule: effectRule, clip: combinedClip, depth: depth)
        return
      }
      let transformed = effectPath.transformed(by: rasterMatrix).rasterPath
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(combinedClip))
        try canvas.fill(transformed, rule: effectRule.raster, paint: try colorSession.resolve(effectPaint))
      }
    }

    private func paintShading(_ shading: GraphicsShading, clip: GraphicsClip) throws {
      let effectiveClip = GraphicsClip(
        imageableBounds: clip.imageableBounds,
        constraints: clip.constraints + (shading.clipPath.map {
          [GraphicsClipConstraint(path: $0, rule: .winding)]
        } ?? [])
      )
      let paints = shading.mesh.triangles.flatMap {
        [$0.first.paint, $0.second.paint, $0.third.paint]
      }
      let resolved = try colorSession.resolve(paints)
      var offset = 0
      let triangles = try shading.mesh.triangles.map { triangle -> RasterGradientTriangle in
        defer { offset += 3 }
        guard case .solid(let firstColor) = resolved[offset],
          case .solid(let secondColor) = resolved[offset + 1],
          case .solid(let thirdColor) = resolved[offset + 2]
        else { throw SolidPostScript.Error.ioError }
        return RasterGradientTriangle(
          first: .init(
            position: rasterMatrix.transform(triangle.first.position).raster,
            color: firstColor
          ),
          second: .init(
            position: rasterMatrix.transform(triangle.second.position).raster,
            color: secondColor
          ),
          third: .init(
            position: rasterMatrix.transform(triangle.third.position).raster,
            color: thirdColor
          )
        )
      }
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(effectiveClip))
        if let background = shading.background {
          try canvas.fill(
            GraphicsPath.rectangle(descriptor.mediaBounds).transformed(by: rasterMatrix).rasterPath,
            rule: .winding,
            paint: try colorSession.resolve(background)
          )
        }
        try canvas.paint(RasterGradientMesh(triangles: triangles))
      }
    }

    private func tileTranslations(for pattern: GraphicsTilingPattern) throws -> [GraphicsMatrix] {
      let origin = pattern.matrix.transform(GraphicsPoint(x: 0, y: 0))
      let requestedXStep = pattern.matrix.transformDistance(GraphicsPoint(x: pattern.xStep, y: 0))
      let requestedYStep = pattern.matrix.transformDistance(GraphicsPoint(x: 0, y: pattern.yStep))
      let xStep = pattern.tilingType == 2 ? requestedXStep : adjustedLatticeStep(requestedXStep)
      let yStep = pattern.tilingType == 2 ? requestedYStep : adjustedLatticeStep(requestedYStep)
      let lattice = GraphicsMatrix(
        a: xStep.x,
        b: xStep.y,
        c: yStep.x,
        d: yStep.y,
        tx: origin.x,
        ty: origin.y
      )
      guard let inverse = lattice.inverted else { throw SolidPostScript.Error.ioError }
      let media = descriptor.mediaBounds
      let coordinates = [
        GraphicsPoint(x: media.x, y: media.y),
        GraphicsPoint(x: media.maxX, y: media.y),
        GraphicsPoint(x: media.maxX, y: media.maxY),
        GraphicsPoint(x: media.x, y: media.maxY),
      ].map(inverse.transform)
      let minimumX = Int((coordinates.map(\.x).min()! - 1).rounded(.down))
      let maximumX = Int((coordinates.map(\.x).max()! + 1).rounded(.up))
      let minimumY = Int((coordinates.map(\.y).min()! - 1).rounded(.down))
      let maximumY = Int((coordinates.map(\.y).max()! + 1).rounded(.up))
      let columns = maximumX - minimumX + 1
      let rows = maximumY - minimumY + 1
      guard columns > 0, rows > 0, rows <= 1_000_000 / columns else {
        throw SolidPostScript.Error.ioError
      }
      var result: [GraphicsMatrix] = []
      result.reserveCapacity(columns * rows)
      for row in minimumY...maximumY {
        for column in minimumX...maximumX {
          let tx = Double(column) * xStep.x + Double(row) * yStep.x
          let ty = Double(column) * xStep.y + Double(row) * yStep.y
          result.append(GraphicsMatrix(
            a: 1,
            b: 0,
            c: 0,
            d: 1,
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

    private func erasePage() throws {
      let clip = GraphicsClip(imageableBounds: descriptor.imageableBounds)
      let mediaPath = GraphicsPath.rectangle(descriptor.mediaBounds).transformed(by: rasterMatrix).rasterPath
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(clip))
        try canvas.fill(mediaPath, rule: .winding, paint: .solid(.white))
      }
    }

    private func draw(
      _ image: RasterImage,
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot
    ) throws {
      let renderedHeight = image.height
      guard descriptor.width > 0,
        renderedHeight > 0,
        renderedHeight <= descriptor.height,
        image.width == descriptor.width
      else { return }
      try withCanvas { canvas in
        try canvas.setClip(try rasterClip(state.clip))
        try canvas.draw(
          image,
          transform: descriptor.imageToDevice.concatenated(with: rasterMatrix).raster,
          interpolation: descriptor.interpolate ? .linear : .nearest
        )
      }
    }

    private func transmitPage() throws {
      guard lifecycle == .active else { throw SolidPostScript.Error.ioError }
      let current = try takeCanvas()
      do {
        let image = try current.finish()
        canvas = nil
        pages.append(image)
      } catch {
        canvas = nil
        throw SolidPostScript.Error.ioError
      }
    }

    private func takeCanvas() throws -> RasterCanvas {
      if let current = canvas.take() {
        return consume current
      }
      return try Self.makePage(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    private func rasterClip(_ clip: GraphicsClip) throws(RasterError) -> RasterClip {
      if clip == cachedGraphicsClip, let cachedRasterClip {
        return cachedRasterClip
      }
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

    private func transformedBounds(_ rect: GraphicsRect, by matrix: GraphicsMatrix) -> GraphicsRect {
      let first = matrix.transform(GraphicsPoint(x: rect.x, y: rect.y))
      let second = matrix.transform(GraphicsPoint(x: rect.maxX, y: rect.y))
      let third = matrix.transform(GraphicsPoint(x: rect.maxX, y: rect.maxY))
      let fourth = matrix.transform(GraphicsPoint(x: rect.x, y: rect.maxY))
      let minimumX = min(first.x, second.x, third.x, fourth.x)
      let maximumX = max(first.x, second.x, third.x, fourth.x)
      let minimumY = min(first.y, second.y, third.y, fourth.y)
      let maximumY = max(first.y, second.y, third.y, fourth.y)
      return GraphicsRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
    }
  }

  /// Device geometry used for each page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// Page width in pixels.
  public let pixelWidth: Int
  /// Page height in pixels.
  public let pixelHeight: Int
  /// The color engine used by this target.
  public let colorEngine: ColorEngine

  /// Creates a bitmap target using an explicit PostScript device descriptor.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    deviceDescriptor: GraphicsDeviceDescriptor,
    colorEngine: ColorEngine
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.deviceDescriptor = deviceDescriptor
    self.colorEngine = colorEngine
  }

  /// Creates a renderer dedicated to one render.
  public func makeRenderer() throws -> sending Renderer {
    try makeRenderer(colorSession: colorEngine.makeSession(for: deviceDescriptor))
  }

  /// Creates a renderer with color conversion state prepared for this render.
  public func makeRenderer(
    colorSession: sending ColorEngine.Session
  ) throws -> sending Renderer {
    try Renderer(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      descriptor: deviceDescriptor,
      colorSession: colorSession
    )
  }
}

/// The native Swift color-managed raster target used by default.
public typealias RasterImageTarget = ColorManagedRasterImageTarget<NativeGraphicsColorEngine>

extension ColorManagedRasterImageTarget where ColorEngine == NativeGraphicsColorEngine {
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
    let media = GraphicsRect(x: 0, y: 0, width: Double(pixelWidth), height: Double(pixelHeight))
    let descriptor = GraphicsDeviceDescriptor(
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
    self.init(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      deviceDescriptor: descriptor,
      colorEngine: NativeGraphicsColorEngine()
    )
  }

  /// Creates a bitmap target using an explicit PostScript device descriptor.
  public init(pixelWidth: Int, pixelHeight: Int, deviceDescriptor: GraphicsDeviceDescriptor) {
    self.init(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      deviceDescriptor: deviceDescriptor,
      colorEngine: NativeGraphicsColorEngine(
        destinationProfile: deviceDescriptor.colorDevice.destinationProfile
      )
    )
  }
}

private extension GraphicsMatrix {
  var raster: RasterAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

private extension GraphicsPoint {
  var raster: RasterPoint { RasterPoint(x: x, y: y) }
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
