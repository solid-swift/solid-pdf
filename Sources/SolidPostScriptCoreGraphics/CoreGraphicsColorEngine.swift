#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import SolidPostScript

/// A Core Graphics color engine targeting an explicit destination color space.
public struct CoreGraphicsColorEngine: GraphicsColorEngine, @unchecked Sendable {
  /// The destination color space shared by render sessions.
  public let destinationColorSpace: CGColorSpace

  /// Creates an engine targeting sRGB by default.
  public init(destinationColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) {
    self.destinationColorSpace = destinationColorSpace
  }

  /// Creates isolated conversion state for one Core Graphics render.
  public func makeSession(
    for device: GraphicsDeviceDescriptor
  ) throws -> sending CoreGraphicsColorSession {
    guard destinationColorSpace.model == .rgb else { throw SolidPostScript.Error.configurationError }
    return CoreGraphicsColorSession(destinationColorSpace: destinationColorSpace)
  }
}

/// Color-session requirements shared by Core Graphics image targets.
public protocol CoreGraphicsCompatibleColorSession: GraphicsColorSession
where ResolvedPaint == CGColor, ImageConverter.ResolvedImage == CGImage {
  /// Destination color space used for page bitmap contexts.
  var destinationColorSpace: CGColorSpace { get }
}

/// Render-scoped Core Graphics color conversion state.
public final class CoreGraphicsColorSession: CoreGraphicsCompatibleColorSession {
  /// The destination color space used by vector paints and images.
  public let destinationColorSpace: CGColorSpace

  /// Creates a session targeting `destinationColorSpace`.
  public init(destinationColorSpace: CGColorSpace) {
    self.destinationColorSpace = destinationColorSpace
  }

  /// Resolves a portable paint into a destination-space color.
  public func resolve(_ paint: GraphicsPaint) throws -> CGColor {
    switch paint {
    case .color(let value):
      return try resolve(value)
    default:
      let rgb = paint.rgbComponents
      return try destinationColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
  }

  /// Creates a bulk image converter for one sampled-image transfer.
  public func makeImageConverter(
    for descriptor: GraphicsImageDescriptor
  ) throws -> sending CoreGraphicsColorImageConverter {
    let byteCapacity = try imageByteCapacity(descriptor)
    let maskComponents: [CGFloat]?
    if case .mask(let paint) = descriptor.kind {
      let sourceSpace = CGColorSpace(name: CGColorSpace.sRGB)!
      guard let color = try resolve(paint).converted(
        to: sourceSpace,
        intent: .relativeColorimetric,
        options: nil
      ) else { throw SolidPostScript.Error.ioError }
      maskComponents = color.components
    } else {
      maskComponents = nil
    }
    return CoreGraphicsColorImageConverter(
      descriptor: descriptor,
      destinationColorSpace: destinationColorSpace,
      maskComponents: maskComponents,
      byteCapacity: byteCapacity
    )
  }

  private func imageByteCapacity(_ descriptor: GraphicsImageDescriptor) throws -> Int {
    let rowBytes = descriptor.width.multipliedReportingOverflow(by: 4)
    guard descriptor.width > 0, descriptor.height > 0, !rowBytes.overflow else {
      throw SolidPostScript.Error.ioError
    }
    let totalBytes = rowBytes.partialValue.multipliedReportingOverflow(by: descriptor.height)
    guard !totalBytes.overflow, totalBytes.partialValue <= 512 * 1_024 * 1_024 else {
      throw SolidPostScript.Error.ioError
    }
    return totalBytes.partialValue
  }

  private func resolve(_ value: GraphicsColorValue) throws -> CGColor {
    switch value {
    case .deviceGray(let gray):
      return try destinationColor(red: gray, green: gray, blue: gray)
    case .deviceRGB(let rgb):
      return try destinationColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
    case .deviceCMYK(let cmyk):
      let rgb = cmyk.rgb
      return try destinationColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
    case .cie(_, _, let xyz, let device):
      if let device { return try resolve(device) }
      guard let xyzSpace = CGColorSpace(name: CGColorSpace.genericXYZ),
        let source = CGColor(
          colorSpace: xyzSpace,
          components: [xyz.x, xyz.y, xyz.z, 1]
        ),
        let converted = source.converted(
          to: destinationColorSpace,
          intent: .relativeColorimetric,
          options: nil
        )
      else { throw SolidPostScript.Error.ioError }
      return converted
    case .named(_, _, _, let alternative):
      return try resolve(alternative)
    }
  }

  private func destinationColor(red: Double, green: Double, blue: Double) throws -> CGColor {
    let sourceSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let source = CGColor(
      colorSpace: sourceSpace,
      components: [red, green, blue, 1]
    ),
      let converted = source.converted(
        to: destinationColorSpace,
        intent: .relativeColorimetric,
        options: nil
      )
    else { throw SolidPostScript.Error.ioError }
    return converted
  }
}

/// Converts ordered semantic rows into a destination-space Core Graphics image.
public final class CoreGraphicsColorImageConverter: GraphicsColorImageConverter {
  private let descriptor: GraphicsImageDescriptor
  private let destinationColorSpace: CGColorSpace
  private let maskComponents: [CGFloat]?
  private var bytes: Data
  private var nextRow = 0
  private var aborted = false

  init(
    descriptor: GraphicsImageDescriptor,
    destinationColorSpace: CGColorSpace,
    maskComponents: [CGFloat]?,
    byteCapacity: Int
  ) {
    self.descriptor = descriptor
    self.destinationColorSpace = destinationColorSpace
    self.maskComponents = maskComponents
    self.bytes = Data(repeating: 0, count: byteCapacity)
  }

  /// Converts and appends a bounded group of complete rows.
  public func write(_ rows: GraphicsImageRows) throws {
    let componentCount = descriptor.kind.componentCount
    let sampleCount = rows.rowCount.multipliedReportingOverflow(by: descriptor.width)
    let expected = sampleCount.partialValue.multipliedReportingOverflow(by: componentCount)
    guard !aborted,
      rows.rowCount > 0,
      rows.startRow == nextRow,
      rows.rowCount <= descriptor.height - nextRow,
      !sampleCount.overflow,
      !expected.overflow,
      rows.components.count == expected.partialValue
    else {
      throw SolidPostScript.Error.ioError
    }
    writeRGBA(
      rows.components,
      componentCount: componentCount,
      destinationOffset: rows.startRow * descriptor.width * 4
    )
    nextRow += rows.rowCount
  }

  /// Completes bulk destination conversion and returns the immutable image.
  public func finish() throws -> sending CGImage {
    guard !aborted else { throw SolidPostScript.Error.ioError }
    let sourceSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let provider = CGDataProvider(data: bytes as CFData),
      let source = CGImage(
        width: descriptor.width,
        height: descriptor.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: descriptor.width * 4,
        space: sourceSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: descriptor.interpolate,
        intent: .relativeColorimetric
      )
    else { throw SolidPostScript.Error.ioError }
    guard destinationColorSpace != sourceSpace else { return source }
    guard let context = CGContext(
      data: nil,
      width: descriptor.width,
      height: descriptor.height,
      bitsPerComponent: 8,
      bytesPerRow: descriptor.width * 4,
      space: destinationColorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw SolidPostScript.Error.ioError }
    context.setBlendMode(.copy)
    context.draw(source, in: CGRect(x: 0, y: 0, width: descriptor.width, height: descriptor.height))
    guard let converted = context.makeImage() else { throw SolidPostScript.Error.ioError }
    return converted
  }

  /// Abandons conversion without producing an image.
  public func abort() {
    aborted = true
    bytes.removeAll()
  }

  private func writeRGBA(_ components: [Float], componentCount: Int, destinationOffset: Int) {
    var destinationOffset = destinationOffset
    for offset in stride(from: 0, to: components.count, by: componentCount) {
      let red: Float
      let green: Float
      let blue: Float
      let alpha: Float
      switch descriptor.kind {
      case .color(.deviceGray):
        red = components[offset]
        green = red
        blue = red
        alpha = 1
      case .color(.deviceRGB):
        red = components[offset]
        green = components[offset + 1]
        blue = components[offset + 2]
        alpha = 1
      case .color(.deviceCMYK):
        let black = components[offset + 3]
        red = 1 - min(1, components[offset] + black)
        green = 1 - min(1, components[offset + 1] + black)
        blue = 1 - min(1, components[offset + 2] + black)
        alpha = 1
      case .mask:
        let color = maskComponents ?? [0, 0, 0, 1]
        alpha = components[offset]
        red = Float(color[0]) * alpha
        green = Float(color[min(1, color.count - 1)]) * alpha
        blue = Float(color[min(2, color.count - 1)]) * alpha
      }
      bytes[destinationOffset] = UInt8((min(1, max(0, red)) * 255).rounded())
      bytes[destinationOffset + 1] = UInt8((min(1, max(0, green)) * 255).rounded())
      bytes[destinationOffset + 2] = UInt8((min(1, max(0, blue)) * 255).rounded())
      bytes[destinationOffset + 3] = UInt8((min(1, max(0, alpha)) * 255).rounded())
      destinationOffset += 4
    }
  }
}
#endif
