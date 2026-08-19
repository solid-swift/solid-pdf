import Foundation
import SolidColor
import SolidPostScript
import SolidRaster

/// A deterministic portable color engine for native Swift raster output.
public struct NativeGraphicsColorEngine: GraphicsColorEngine, Sendable {
  /// The destination profile used by new render sessions.
  public let destinationProfile: ColorDestinationProfile

  /// Creates an engine targeting sRGB by default.
  public init(destinationProfile: ColorDestinationProfile = .sRGB) {
    self.destinationProfile = destinationProfile
  }

  /// Creates isolated conversion state for one raster render.
  public func makeSession(
    for device: GraphicsDeviceDescriptor
  ) throws -> sending NativeGraphicsColorSession {
    guard destinationProfile.model == .rgb else { throw SolidPostScript.Error.configurationError }
    return try NativeGraphicsColorSession(destinationProfile: destinationProfile)
  }
}

/// Render-scoped native Swift color conversion state.
public final class NativeGraphicsColorSession: GraphicsColorSession {
  private let converter: NativeColorConverter

  /// Creates a session for `destinationProfile`.
  public init(destinationProfile: ColorDestinationProfile = .sRGB) throws {
    guard destinationProfile.model == .rgb else { throw SolidPostScript.Error.configurationError }
    converter = NativeColorConverter(destination: destinationProfile)
  }

  /// Resolves a semantic paint into a native raster paint.
  public func resolve(_ paint: GraphicsPaint) throws -> RasterPaint {
    let rgb = try resolvedRGB(paint)
    return .solid(RasterColor(red: rgb.red, green: rgb.green, blue: rgb.blue))
  }

  /// Resolves a paint and applies its captured device transfer functions.
  public func resolve(
    _ paint: GraphicsPaint,
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> RasterPaint {
    let rgb = try resolvedRGB(paint)
    return .solid(RasterColor(
      red: clipped(deviceRendering.transferFunctions.red.evaluate(rgb.red)),
      green: clipped(deviceRendering.transferFunctions.green.evaluate(rgb.green)),
      blue: clipped(deviceRendering.transferFunctions.blue.evaluate(rgb.blue))
    ))
  }

  /// Creates an ordered image converter for one sampled image.
  public func makeImageConverter(
    for descriptor: GraphicsImageDescriptor
  ) throws -> sending NativeGraphicsColorImageConverter {
    let byteCapacity = try imageByteCapacity(descriptor)
    let maskPaint: RasterPaint?
    if case .mask(let paint) = descriptor.kind {
      maskPaint = try resolve(paint)
    } else {
      maskPaint = nil
    }
    return NativeGraphicsColorImageConverter(
      descriptor: descriptor,
      maskPaint: maskPaint,
      byteCapacity: byteCapacity,
      transferFunctions: .identity
    )
  }

  /// Creates an image converter that applies captured transfer functions.
  public func makeImageConverter(
    for descriptor: GraphicsImageDescriptor,
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> sending NativeGraphicsColorImageConverter {
    let byteCapacity = try imageByteCapacity(descriptor)
    let maskPaint: RasterPaint?
    if case .mask(let paint) = descriptor.kind {
      maskPaint = try resolve(paint, deviceRendering: deviceRendering)
    } else {
      maskPaint = nil
    }
    return NativeGraphicsColorImageConverter(
      descriptor: descriptor,
      maskPaint: maskPaint,
      byteCapacity: byteCapacity,
      transferFunctions: deviceRendering.transferFunctions
    )
  }

  private func resolvedRGB(_ paint: GraphicsPaint) throws -> ColorRGB {
    switch paint {
    case .deviceGray(let gray):
      return .init(red: gray, green: gray, blue: gray)
    case .deviceRGB(let red, let green, let blue):
      return .init(red: red, green: green, blue: blue)
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      return ColorCMYK(cyan: cyan, magenta: magenta, yellow: yellow, black: black).rgb
    case .color(let value):
      return try resolvedRGB(value)
    case .pattern:
      throw SolidPostScript.Error.ioError
    }
  }

  private func resolvedRGB(_ value: GraphicsColorValue) throws -> ColorRGB {
    switch value {
    case .deviceGray(let gray):
      return .init(red: gray, green: gray, blue: gray)
    case .deviceRGB(let rgb):
      return rgb.clamped
    case .deviceCMYK(let cmyk):
      return cmyk.rgb
    case .cie(_, _, let xyz, let device):
      if let device { return try resolvedRGB(device) }
      do {
        return try converter.rgb(from: xyz)
      } catch {
        throw SolidPostScript.Error.ioError
      }
    case .named(_, _, _, let alternative):
      return try resolvedRGB(alternative)
    }
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

  private func clipped(_ value: Double) -> Double { min(1, max(0, value)) }
}

/// Incrementally converts semantic image rows into a native raster image.
public final class NativeGraphicsColorImageConverter: GraphicsColorImageConverter {
  private let descriptor: GraphicsImageDescriptor
  private let maskPaint: RasterPaint?
  private var bytes: Data
  private var nextRow = 0
  private var aborted = false
  private let transferFunctions: GraphicsTransferFunctions

  init(
    descriptor: GraphicsImageDescriptor,
    maskPaint: RasterPaint?,
    byteCapacity: Int,
    transferFunctions: GraphicsTransferFunctions
  ) {
    self.descriptor = descriptor
    self.maskPaint = maskPaint
    self.bytes = Data(repeating: 0, count: byteCapacity)
    self.transferFunctions = transferFunctions
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

  /// Completes conversion and returns the immutable image.
  public func finish() throws -> sending RasterImage {
    guard !aborted else { throw SolidPostScript.Error.ioError }
    do {
      return try RasterImage(
        width: descriptor.width,
        height: descriptor.height,
        bytesPerRow: descriptor.width * 4,
        pixelFormat: .rgba8UnormPremultiplied,
        data: bytes
      )
    } catch {
      throw SolidPostScript.Error.ioError
    }
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
        let color = maskPaint?.solidColor ?? .black
        alpha = components[offset]
        red = Float(color.red) * alpha
        green = Float(color.green) * alpha
        blue = Float(color.blue) * alpha
      }
      let transferredRed = transferFunctions.red.evaluate(Double(red))
      let transferredGreen = transferFunctions.green.evaluate(Double(green))
      let transferredBlue = transferFunctions.blue.evaluate(Double(blue))
      bytes[destinationOffset] = UInt8((min(1, max(0, transferredRed)) * 255).rounded())
      bytes[destinationOffset + 1] = UInt8((min(1, max(0, transferredGreen)) * 255).rounded())
      bytes[destinationOffset + 2] = UInt8((min(1, max(0, transferredBlue)) * 255).rounded())
      bytes[destinationOffset + 3] = UInt8((min(1, max(0, alpha)) * 255).rounded())
      destinationOffset += 4
    }
  }
}

private extension RasterPaint {
  var solidColor: RasterColor? {
    if case .solid(let color) = self { return color }
    return nil
  }
}
