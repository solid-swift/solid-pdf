#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import SolidPostScript

/// A PostScript graphics target that produces one bitmap image for each transmitted page.
public struct CoreGraphicsImageTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = CGImage
  public typealias Output = [CGImage]

  /// The renderer dedicated to one Core Graphics image render.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = CGImage
    public typealias Output = [CGImage]

    /// Images transmitted by `showpage` so far.
    public private(set) var pages: [CGImage] = []

    private let pixelWidth: Int
    private let pixelHeight: Int
    private let descriptor: GraphicsDeviceDescriptor
    private var context: CGContext?
    private var activeImage: (descriptor: GraphicsImageDescriptor, state: GraphicsStateSnapshot, components: [Float])?
    private static let maximumBitmapBytes = 512 * 1_024 * 1_024

    fileprivate init(pixelWidth: Int, pixelHeight: Int, descriptor: GraphicsDeviceDescriptor) throws {
      self.pixelWidth = pixelWidth
      self.pixelHeight = pixelHeight
      self.descriptor = descriptor
      self.context = try Self.makePage(
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        descriptor: descriptor
      )
    }

    /// Processes one graphics event using its authoritative state snapshots.
    public func process(_ event: GraphicsEvent) throws {
      guard let context else { throw SolidPostScript.Error.ioError }
      switch event.operation {
      case .paint(.erasePage):
        erasePage(context)
      case .paint(.fill(let rule)):
        fill(event.before.path, rule: rule, state: event.before, in: context)
      case .paint(.stroke):
        try stroke(event.before.path, state: event.before, in: context)
      case .paint(.fillRectangles(let paths)):
        fillRectangles(paths, state: event.before, in: context)
      case .paint(.strokeRectangles(let paths, let matrix)):
        try strokeRectangles(paths, matrix: matrix, state: event.before, in: context)
      case .page(.show), .page(.copy):
        guard let image = context.makeImage() else { throw SolidPostScript.Error.ioError }
        let next = try Self.makePage(
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          descriptor: descriptor
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
      activeImage = (descriptor, event.before, [])
    }

    /// Consumes one bounded group of complete sampled-image rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard var image = activeImage else { throw SolidPostScript.Error.ioError }
      let expectedStart = image.components.count / (image.descriptor.width * image.descriptor.kind.componentCount)
      let expectedCount = rows.rowCount * image.descriptor.width * image.descriptor.kind.componentCount
      guard rows.startRow == expectedStart, rows.components.count == expectedCount else {
        throw SolidPostScript.Error.ioError
      }
      image.components.append(contentsOf: rows.components)
      activeImage = image
    }

    /// Commits and paints the active sampled image.
    public func endImage() throws {
      guard let image = activeImage, let context else { throw SolidPostScript.Error.ioError }
      activeImage = nil
      try draw(GraphicsImage(descriptor: image.descriptor, components: image.components), state: image.state, in: context)
    }

    /// Abandons the active sampled image without painting it.
    public func abortImage() {
      activeImage = nil
    }

    /// Completes the job and discards the current untransmitted page.
    public func finish() -> sending [CGImage] {
      activeImage = nil
      context = nil
      return pages
    }

    /// Abandons the current page and all transmitted output.
    public func abort() {
      activeImage = nil
      context = nil
      pages.removeAll()
    }

    private static func makePage(
      pixelWidth: Int,
      pixelHeight: Int,
      descriptor: GraphicsDeviceDescriptor
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
        space: CGColorSpaceCreateDeviceRGB(),
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
    ) {
      context.saveGState()
      replay(state.clip, in: context)
      context.addPath(path.cgPath)
      setPaint(state.paint, in: context)
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
      if state.strokeAdjustment {
        let outline = try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
        fill(outline, rule: .winding, state: state, in: context)
        return
      }
      guard let inverse = matrix.inverted else { return }
      context.saveGState()
      replay(state.clip, in: context)
      context.concatenate(matrix.cgAffineTransform)
      context.addPath(path.transformed(by: inverse).cgPath)
      setPaint(state.paint, in: context)
      context.setLineWidth(state.lineWidth)
      context.setLineCap(state.lineCap.cgLineCap)
      context.setLineJoin(state.lineJoin.cgLineJoin)
      context.setMiterLimit(state.miterLimit)
      context.setLineDash(phase: state.dash.phase, lengths: state.dash.pattern.map { CGFloat($0) })
      context.strokePath()
      context.restoreGState()
    }

    private func fillRectangles(
      _ paths: [GraphicsPath],
      state: GraphicsStateSnapshot,
      in context: CGContext
    ) {
      context.saveGState()
      replay(state.clip, in: context)
      for path in paths { context.addPath(path.cgPath) }
      setPaint(state.paint, in: context)
      context.fillPath()
      context.restoreGState()
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
      }
    }

    private func draw(
      _ image: GraphicsImage,
      state: GraphicsStateSnapshot,
      in context: CGContext
    ) throws {
      let descriptor = image.descriptor
      let rowWidth = descriptor.width * descriptor.kind.componentCount
      let renderedHeight = rowWidth == 0 ? 0 : image.components.count / rowWidth
      guard descriptor.width > 0,
        renderedHeight > 0,
        renderedHeight <= descriptor.height,
        image.components.count == renderedHeight * rowWidth
      else { return }
      let data = image.premultipliedRGBA8() as CFData
      guard let provider = CGDataProvider(data: data),
        let cgImage = CGImage(
          width: descriptor.width,
          height: renderedHeight,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: descriptor.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: descriptor.interpolate,
          intent: .defaultIntent
        )
      else {
        throw SolidPostScript.Error.ioError
      }
      context.saveGState()
      replay(state.clip, in: context)
      context.concatenate(descriptor.imageToDevice.cgAffineTransform)
      context.interpolationQuality = descriptor.interpolate ? .high : .none
      context.draw(
        cgImage,
          in: CGRect(x: 0, y: 0, width: descriptor.width, height: renderedHeight)
      )
      context.restoreGState()
    }

    private func setPaint(_ paint: GraphicsPaint, in context: CGContext) {
      switch paint {
      case .deviceGray(let gray):
        context.setFillColor(gray: gray, alpha: 1)
        context.setStrokeColor(gray: gray, alpha: 1)
      case .deviceRGB, .deviceCMYK:
        let rgb = paint.rgbComponents
        context.setFillColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        context.setStrokeColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
      }
    }
  }

  /// The device geometry and default transformation used for each page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The page width in pixels.
  public let pixelWidth: Int
  /// The page height in pixels.
  public let pixelHeight: Int

  /// Creates an RGBA bitmap target with explicit pixel geometry and resolution.
  public init(
    pixelWidth: Int,
    pixelHeight: Int,
    resolution: Double = 72,
    imageableBounds: GraphicsRect? = nil
  ) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
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
    try Renderer(pixelWidth: pixelWidth, pixelHeight: pixelHeight, descriptor: deviceDescriptor)
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
