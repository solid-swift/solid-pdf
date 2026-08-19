#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import SolidPostScript
import SolidRaster

/// A Core Graphics image target parameterized by a compatible color engine.
public struct ColorManagedCoreGraphicsImageTarget<ColorEngine: GraphicsColorEngine>: GraphicsTarget, Sendable
where
  ColorEngine.Session: CoreGraphicsCompatibleColorSession
{
  public typealias PageOutput = CGImage
  public typealias Output = [CGImage]

  /// The renderer dedicated to one Core Graphics image render.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = CGImage
    public typealias Output = [CGImage]
    public typealias ColorSession = ColorEngine.Session

    /// Images transmitted by `showpage` so far.
    public private(set) var pages: [CGImage] = []

    private let pixelWidth: Int
    private let pixelHeight: Int
    private let descriptor: GraphicsDeviceDescriptor
    private let colorSession: ColorEngine.Session
    private let rasterMatrix: GraphicsMatrix
    private var context: CGContext?
    private var activeImage: (
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      converter: ColorEngine.Session.ImageConverter,
      maskOpacities: [Float],
      nextMaskRow: Int
    )?
    private static var maximumBitmapBytes: Int { 512 * 1_024 * 1_024 }

    fileprivate init(
      pixelWidth: Int,
      pixelHeight: Int,
      descriptor: GraphicsDeviceDescriptor,
      colorSession: ColorEngine.Session
    ) throws {
      guard colorSession.destinationColorSpace.model == .rgb else {
        throw SolidPostScript.Error.configurationError
      }
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
      self.context = try Self.makePage(
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        descriptor: descriptor,
        colorSpace: colorSession.destinationColorSpace
      )
    }

    /// Processes one graphics event using its authoritative state snapshots.
    public func process(_ event: GraphicsEvent) throws {
      guard let context else { throw SolidPostScript.Error.ioError }
      switch event.operation {
      case .paint(.erasePage):
        erasePage(context)
      case .paint(.fill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before, in: context)
      case .paint(.stroke):
        try stroke(event.before.path, state: event.before, in: context)
      case .paint(.userPathFill(let rule)):
        try fill(event.before.path, rule: rule, state: event.before, in: context)
      case .paint(.userPathStroke):
        try fill(event.before.path, rule: .winding, state: event.before, in: context)
      case .paint(.fillRectangles(let paths)):
        try fill(
          GraphicsPath(elements: paths.flatMap(\.elements)),
          rule: .winding,
          state: event.before,
          in: context
        )
      case .paint(.strokeRectangles(let paths, let matrix)):
        try strokeRectangles(paths, matrix: matrix, state: event.before, in: context)
      case .paint(.shading(let shading)):
        try paintShading(shading, clip: event.before.clip, in: context)
      case .paint(.form(let form)):
        try paintForm(form, in: context, depth: 0)
      case .page(.show), .page(.copy):
        guard let image = context.makeImage() else { throw SolidPostScript.Error.ioError }
        let next = try Self.makePage(
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          descriptor: descriptor,
          colorSpace: colorSession.destinationColorSpace
        )
        pages.append(image)
        self.context = next
      default:
        break
      }
    }

    /// Begins one sampled-image transfer.
    public func beginImage(_ event: GraphicsEvent) throws {
      guard activeImage == nil, case .paint(.image(let descriptor)) = event.operation else {
        throw SolidPostScript.Error.ioError
      }
      activeImage = (
        descriptor,
        event.before,
        try colorSession.makeImageConverter(for: descriptor),
        [],
        0
      )
    }

    /// Consumes one bounded group of complete sampled-image rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard let image = activeImage else { throw SolidPostScript.Error.ioError }
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
      image.maskOpacities.append(contentsOf: rows.opacities)
      image.nextMaskRow += rows.rowCount
      activeImage = image
    }

    /// Commits and paints the active sampled image.
    public func endImage() throws {
      guard let image = activeImage, let context else { throw SolidPostScript.Error.ioError }
      activeImage = nil
      try draw(
        image.converter.finish(),
        descriptor: image.descriptor,
        state: image.state,
        mask: try rasterMask(descriptor: image.descriptor, opacities: image.maskOpacities),
        in: context
      )
    }

    /// Abandons the active sampled image without painting it.
    public func abortImage() {
      activeImage?.converter.abort()
      activeImage = nil
    }

    /// Completes the job and discards the current untransmitted page.
    public func finish() -> sending [CGImage] {
      activeImage?.converter.abort()
      activeImage = nil
      context = nil
      return pages
    }

    /// Abandons the current page and all transmitted output.
    public func abort() {
      activeImage?.converter.abort()
      activeImage = nil
      context = nil
      pages.removeAll()
    }

    private static func makePage(
      pixelWidth: Int,
      pixelHeight: Int,
      descriptor: GraphicsDeviceDescriptor,
      colorSpace: CGColorSpace
    ) throws -> CGContext {
      guard pixelWidth > 0,
        pixelHeight > 0,
        pixelWidth <= Int.max / 4,
        pixelHeight <= Int.max / (pixelWidth * 4),
        pixelHeight <= maximumBitmapBytes / (pixelWidth * 4),
        descriptor.horizontalResolution.isFinite,
        descriptor.verticalResolution.isFinite,
        descriptor.horizontalResolution > 0,
        descriptor.verticalResolution > 0,
        descriptor.imageableBounds.x >= descriptor.mediaBounds.x,
        descriptor.imageableBounds.y >= descriptor.mediaBounds.y,
        descriptor.imageableBounds.maxX <= descriptor.mediaBounds.maxX,
        descriptor.imageableBounds.maxY <= descriptor.mediaBounds.maxY
      else {
        throw SolidPostScript.Error.configurationError
      }
      guard let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: pixelWidth * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
        throw SolidPostScript.Error.ioError
      }
      context.setFillColor(gray: 1, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      context.clip(to: descriptor.imageableBounds.cgRect)
      return context
    }

    private func erasePage(_ context: CGContext) {
      context.saveGState()
      context.setFillColor(gray: 1, alpha: 1)
      context.fill(descriptor.mediaBounds.cgRect)
      context.restoreGState()
    }

    private func fill(
      _ path: GraphicsPath,
      rule: GraphicsFillRule,
      state: GraphicsStateSnapshot,
      in context: CGContext
    ) throws {
      if case .pattern(let pattern) = state.paint {
        try fillPattern(pattern, through: path, rule: rule, state: state, in: context, depth: 0)
        return
      }
      context.saveGState()
      replay(state.clip, in: context)
      context.addPath(path.cgPath)
      try setPaint(state.paint, in: context)
      context.drawPath(using: rule == .evenOdd ? .eoFill : .fill)
      context.restoreGState()
    }

    private func stroke(_ path: GraphicsPath, state: GraphicsStateSnapshot, in context: CGContext) throws {
      try stroke(path, matrix: state.matrix, state: state, in: context)
    }

    private func stroke(
      _ path: GraphicsPath,
      matrix: GraphicsMatrix,
      state: GraphicsStateSnapshot,
      in context: CGContext
    ) throws {
      if case .pattern = state.paint {
        let outline = try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
        try fill(outline, rule: .winding, state: state, in: context)
        return
      }
      if state.strokeAdjustment {
        let outline = try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
        try fill(outline, rule: .winding, state: state, in: context)
        return
      }
      guard let inverse = matrix.inverted else { return }
      context.saveGState()
      replay(state.clip, in: context)
      context.concatenate(matrix.cgAffineTransform)
      context.addPath(path.transformed(by: inverse).cgPath)
      try setPaint(state.paint, in: context)
      context.setLineWidth(state.lineWidth)
      context.setLineCap(state.lineCap.cgLineCap)
      context.setLineJoin(state.lineJoin.cgLineJoin)
      context.setMiterLimit(state.miterLimit)
      context.setLineDash(phase: state.dash.phase, lengths: state.dash.pattern.map { CGFloat($0) })
      context.strokePath()
      context.restoreGState()
    }

    private func fillPattern(
      _ paint: GraphicsPatternPaint,
      through path: GraphicsPath,
      rule: GraphicsFillRule,
      state: GraphicsStateSnapshot,
      in context: CGContext,
      depth: Int
    ) throws {
      guard depth < 16 else { throw SolidPostScript.Error.ioError }
      switch paint {
      case .empty:
        return
      case .shading(let shading):
        try paintShading(shading, clip: nil, in: context)
      case .tiling(let pattern, let underlying):
        context.saveGState()
        defer { context.restoreGState() }
        replay(state.clip, in: context)
        context.addPath(path.cgPath)
        if rule == .evenOdd { context.clip(using: .evenOdd) } else { context.clip() }
        context.beginPath()
        for translation in try tileTranslations(for: pattern) {
          for effect in pattern.displayList.effects {
            try replayPatternEffect(
              effect,
              translation: translation,
              underlying: underlying,
              in: context,
              depth: depth + 1
            )
          }
        }
      }
    }

    private func paintForm(_ form: GraphicsForm, in context: CGContext, depth: Int) throws {
      guard depth < 16 else { throw SolidPostScript.Error.ioError }
      for effect in form.displayList.effects {
        try replayFormEffect(effect, in: context, depth: depth + 1)
      }
    }

    private func replayFormEffect(_ effect: GraphicsEffect, in context: CGContext, depth: Int) throws {
      switch effect {
      case .fill(let path, let rule, let state), .userPathFill(let path, let rule, let state):
        try fill(path, rule: rule, state: state, in: context)
      case .stroke(let path, let state):
        try stroke(path, state: state, in: context)
      case .userPathStroke(let outline, let state):
        try fill(outline, rule: .winding, state: state, in: context)
      case .erase:
        erasePage(context)
      case .fillRectangles(let paths, let state):
        try fill(
          GraphicsPath(elements: paths.flatMap(\.elements)),
          rule: .winding,
          state: state,
          in: context
        )
      case .strokeRectangles(let paths, let matrix, let state):
        try strokeRectangles(paths, matrix: matrix, state: state, in: context)
      case .image(let image, let state):
        let converter = try colorSession.makeImageConverter(for: image.descriptor)
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
            in: context
          )
        } catch {
          converter.abort()
          throw error
        }
      case .shading(let shading, let state):
        try paintShading(shading, clip: state.clip, in: context)
      case .form(let nested, _):
        try paintForm(nested, in: context, depth: depth)
      }
    }

    private func replayPatternEffect(
      _ effect: GraphicsEffect,
      translation: GraphicsMatrix,
      underlying: GraphicsPaint?,
      in context: CGContext,
      depth: Int
    ) throws {
      if case .image(let image, let imageState) = effect {
        let translatedConstraints = imageState.clip.constraints.map {
          GraphicsClipConstraint(path: $0.path.transformed(by: translation), rule: $0.rule)
        }
        let combinedClip = GraphicsClip(
          imageableBounds: imageState.clip.imageableBounds,
          constraints: translatedConstraints
        )
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
        let converter = try colorSession.makeImageConverter(for: descriptor)
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
            clip: combinedClip,
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
            pathBoundingBox: imageState.pathBoundingBox
          )
          try draw(
            converter.finish(),
            descriptor: descriptor,
            state: state,
            mask: try rasterMask(descriptor: descriptor, opacities: image.mask?.opacities ?? []),
            in: context
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
      case .form(let form, _):
        guard depth < 16 else { throw SolidPostScript.Error.ioError }
        for nested in form.displayList.effects {
          try replayPatternEffect(
            nested,
            translation: translation,
            underlying: underlying,
            in: context,
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
        let translated = translatedShading(shading, by: translation)
        let translatedClip = GraphicsClip(
          imageableBounds: shadingState.clip.imageableBounds,
          constraints: shadingState.clip.constraints.map {
            .init(path: $0.path.transformed(by: translation), rule: $0.rule)
          }
        )
        try paintShading(translated, clip: translatedClip, in: context)
        return
      }
      let selectedPaint = underlying ?? state.paint
      if case .pattern(let nested) = selectedPaint {
        try fillPattern(nested, through: path, rule: rule, state: state, in: context, depth: depth)
        return
      }
      context.saveGState()
      defer { context.restoreGState() }
      for constraint in state.clip.constraints {
        context.addPath(constraint.path.transformed(by: translation).cgPath)
        if constraint.rule == .evenOdd { context.clip(using: .evenOdd) } else { context.clip() }
        context.beginPath()
      }
      context.addPath(path.cgPath)
      try setPaint(selectedPaint, in: context)
      context.drawPath(using: rule == .evenOdd ? .eoFill : .fill)
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
      guard maxX - minX + 1 <= 1_000_000 / max(1, maxY - minY + 1) else {
        throw SolidPostScript.Error.ioError
      }
      return (minY...maxY).flatMap { row in
        (minX...maxX).map { column in
          {
            let tx = Double(column) * xStep.x + Double(row) * yStep.x
            let ty = Double(column) * xStep.y + Double(row) * yStep.y
            return GraphicsMatrix(
            a: 1, b: 0, c: 0, d: 1,
            tx: pattern.tilingType == 2 ? tx.rounded() : tx,
            ty: pattern.tilingType == 2 ? ty.rounded() : ty
          )
          }()
        }
      }
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
      in context: CGContext
    ) throws {
      context.saveGState()
      replay(state.clip, in: context)
      for path in paths { context.addPath(path.cgPath) }
      try setPaint(state.paint, in: context)
      context.fillPath()
      context.restoreGState()
    }

    private func paintShading(
      _ shading: GraphicsShading,
      clip: GraphicsClip?,
      in context: CGContext
    ) throws {
      let paints = shading.mesh.triangles.flatMap {
        [$0.first.paint, $0.second.paint, $0.third.paint]
      }
      let colors = try colorSession.resolve(paints)
      var offset = 0
      let rasterMatrix = GraphicsMatrix(
        a: 1, b: 0, c: 0, d: -1,
        tx: -descriptor.mediaBounds.x,
        ty: descriptor.mediaBounds.maxY
      )
      let triangles = try shading.mesh.triangles.map { triangle -> RasterGradientTriangle in
        defer { offset += 3 }
        return RasterGradientTriangle(
          first: .init(
            position: rasterMatrix.transform(triangle.first.position).raster,
            color: try rasterColor(colors[offset])
          ),
          second: .init(
            position: rasterMatrix.transform(triangle.second.position).raster,
            color: try rasterColor(colors[offset + 1])
          ),
          third: .init(
            position: rasterMatrix.transform(triangle.third.position).raster,
            color: try rasterColor(colors[offset + 2])
          )
        )
      }
      var canvas = try RasterCanvas(
        width: pixelWidth,
        height: pixelHeight,
        background: RasterColor(red: 0, green: 0, blue: 0, alpha: 0)
      )
      try canvas.paint(RasterGradientMesh(triangles: triangles))
      let image = try canvas.finish().cgImage(colorSpace: colorSession.destinationColorSpace)
      context.saveGState()
      defer { context.restoreGState() }
      if let clip { replay(clip, in: context) }
      if let clipPath = shading.clipPath {
        context.addPath(clipPath.cgPath)
        context.clip()
        context.beginPath()
      }
      if let background = shading.background {
        try setPaint(background, in: context)
        context.fill(descriptor.mediaBounds.cgRect)
      }
      context.draw(image, in: descriptor.mediaBounds.cgRect)
    }

    private func rasterColor(_ color: CGColor) throws -> RasterColor {
      guard let components = color.components, components.count >= 3 else {
        throw SolidPostScript.Error.ioError
      }
      return RasterColor(
        red: Double(components[0]),
        green: Double(components[1]),
        blue: Double(components[2]),
        alpha: Double(color.alpha)
      )
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
      in context: CGContext
    ) throws {
      let path = GraphicsPath(elements: paths.flatMap(\.elements))
      let effectiveMatrix = matrix?.concatenated(with: state.matrix) ?? state.matrix
      try stroke(path, matrix: effectiveMatrix, state: state, in: context)
    }

    private func replay(_ clip: GraphicsClip, in context: CGContext) {
      context.clip(to: clip.imageableBounds.cgRect)
      for constraint in clip.constraints {
        context.addPath(constraint.path.cgPath)
        if constraint.rule == .evenOdd {
          context.clip(using: .evenOdd)
        } else {
          context.clip()
        }
        context.beginPath()
      }
    }

    private func draw(
      _ image: CGImage,
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      mask: RasterMask? = nil,
      in context: CGContext
    ) throws {
      let renderedHeight = image.height
      guard descriptor.width > 0,
        renderedHeight > 0,
        renderedHeight <= descriptor.height,
        image.width == descriptor.width
      else { return }
      if let mask {
        if try drawNativeAlignedMaskedImage(
          image,
          mask: mask,
          descriptor: descriptor,
          state: state,
          in: context
        ) {
          return
        }
        try drawPortableMaskedImage(image, mask: mask, descriptor: descriptor, state: state, in: context)
        return
      }
      context.saveGState()
      replay(state.clip, in: context)
      context.concatenate(descriptor.imageToDevice.cgAffineTransform)
      context.interpolationQuality = descriptor.interpolate ? .high : .none
      context.draw(
        image,
          in: CGRect(x: 0, y: 0, width: descriptor.width, height: renderedHeight)
      )
      context.restoreGState()
    }

    private func drawNativeAlignedMaskedImage(
      _ image: CGImage,
      mask: RasterMask,
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      in context: CGContext
    ) throws -> Bool {
      let maskTransform: GraphicsMatrix
      let maskInterpolation: Bool
      switch descriptor.mask {
      case .explicit(let width, let height, let transform, let interpolate):
        guard width == descriptor.width, height == descriptor.height else { return false }
        maskTransform = transform
        maskInterpolation = interpolate
      case .colorKey:
        maskTransform = descriptor.imageToDevice
        maskInterpolation = descriptor.interpolate
      case nil:
        return false
      }
      guard mask.width == descriptor.width,
        mask.height == descriptor.height,
        maskTransform == descriptor.imageToDevice,
        maskInterpolation == descriptor.interpolate,
        let provider = CGDataProvider(data: mask.data as CFData),
        let maskImage = CGImage(
          width: mask.width,
          height: mask.height,
          bitsPerComponent: 8,
          bitsPerPixel: 8,
          bytesPerRow: mask.bytesPerRow,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: maskInterpolation,
          intent: .defaultIntent
        )
      else { throw SolidPostScript.Error.ioError }

      context.saveGState()
      defer { context.restoreGState() }
      replay(state.clip, in: context)
      context.concatenate(descriptor.imageToDevice.cgAffineTransform)
      let bounds = CGRect(x: 0, y: 0, width: descriptor.width, height: image.height)
      context.clip(to: bounds, mask: maskImage)
      context.interpolationQuality = descriptor.interpolate ? .high : .none
      context.draw(image, in: bounds)
      return true
    }

    private func drawPortableMaskedImage(
      _ image: CGImage,
      mask: RasterMask,
      descriptor: GraphicsImageDescriptor,
      state: GraphicsStateSnapshot,
      in context: CGContext
    ) throws {
      let rasterImage = try rasterImage(image)
      do {
        var canvas = try RasterCanvas(width: pixelWidth, height: pixelHeight)
        try canvas.setClip(RasterClip(
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
        try canvas.draw(
          rasterImage,
          transform: descriptor.imageToDevice.concatenated(with: rasterMatrix).raster,
          interpolation: descriptor.interpolate ? .linear : .nearest,
          mask: mask,
          maskTransform: maskTransform.concatenated(with: rasterMatrix).raster,
          maskInterpolation: maskInterpolation
        )
        let overlay = try canvas.finish(pixelFormat: .rgba8UnormPremultiplied)
        guard let provider = CGDataProvider(data: overlay.data as CFData),
          let overlayImage = CGImage(
            width: overlay.width,
            height: overlay.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: overlay.bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .relativeColorimetric
          )
        else { throw SolidPostScript.Error.ioError }
        context.saveGState()
        context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: Double(pixelHeight)))
        context.draw(overlayImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.restoreGState()
      } catch {
        throw SolidPostScript.Error.ioError
      }
    }

    private func rasterImage(_ image: CGImage) throws -> RasterImage {
      var data = Data(repeating: 0, count: image.width * image.height * 4)
      let created = data.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
          data: bytes.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
      }
      guard created else { throw SolidPostScript.Error.ioError }
      do {
        return try RasterImage(
          width: image.width,
          height: image.height,
          bytesPerRow: image.width * 4,
          pixelFormat: .rgba8UnormPremultiplied,
          data: data
        )
      } catch {
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

    private func setPaint(_ paint: GraphicsPaint, in context: CGContext) throws {
      let color = try colorSession.resolve(paint)
      context.setFillColor(color)
      context.setStrokeColor(color)
    }
  }

  /// The device geometry and default transformation used for each page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The page width in pixels.
  public let pixelWidth: Int
  /// The page height in pixels.
  public let pixelHeight: Int
  /// The color engine used by this target.
  public let colorEngine: ColorEngine

  /// Creates an RGBA bitmap target with explicit pixel geometry and resolution.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    resolution: Double = 72,
    imageableBounds: GraphicsRect? = nil,
    colorEngine: ColorEngine
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.colorEngine = colorEngine
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

  /// Creates a renderer dedicated to one render operation.
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

/// The Core Graphics color-managed image target used by default.
public typealias CoreGraphicsImageTarget = ColorManagedCoreGraphicsImageTarget<CoreGraphicsColorEngine>

extension ColorManagedCoreGraphicsImageTarget where ColorEngine == CoreGraphicsColorEngine {
  /// Creates an RGBA bitmap target with explicit geometry and destination color space.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    resolution: Double = 72,
    imageableBounds: GraphicsRect? = nil,
    destinationColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  ) {
    self.init(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      resolution: resolution,
      imageableBounds: imageableBounds,
      colorEngine: CoreGraphicsColorEngine(destinationColorSpace: destinationColorSpace)
    )
  }
}

private extension GraphicsRect {
  var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

private extension GraphicsMatrix {
  var cgAffineTransform: CGAffineTransform {
    CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
  }
}

private extension GraphicsPath {
  static func rectangle(_ rect: GraphicsRect) -> Self {
    Self(elements: [
      .move(to: GraphicsPoint(x: rect.x, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.maxY)),
      .line(to: GraphicsPoint(x: rect.x, y: rect.maxY)),
      .close,
    ])
  }

  var cgPath: CGPath {
    let path = CGMutablePath()
    for element in elements {
      switch element {
      case .move(let point):
        path.move(to: point.cgPoint)
      case .line(let point):
        path.addLine(to: point.cgPoint)
      case .curve(let control1, let control2, let end):
        path.addCurve(to: end.cgPoint, control1: control1.cgPoint, control2: control2.cgPoint)
      case .close:
        path.closeSubpath()
      }
    }
    return path
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
  var cgPoint: CGPoint { CGPoint(x: x, y: y) }
  var raster: RasterPoint { RasterPoint(x: x, y: y) }
}

private extension GraphicsMatrix {
  var raster: RasterAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

private extension GraphicsRect {
  var raster: RasterRect { .init(x: x, y: y, width: width, height: height) }
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
}

private extension RasterImage {
  func cgImage(colorSpace: CGColorSpace) throws -> CGImage {
    guard let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
      )
    else { throw SolidPostScript.Error.ioError }
    return image
  }
}

private extension GraphicsLineCap {
  var cgLineCap: CGLineCap {
    switch self {
    case .butt: .butt
    case .round: .round
    case .square: .square
    }
  }
}

private extension GraphicsLineJoin {
  var cgLineJoin: CGLineJoin {
    switch self {
    case .miter: .miter
    case .round: .round
    case .bevel: .bevel
    }
  }
}
#endif
