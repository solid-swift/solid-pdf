import Foundation

enum RasterCompositor {
  static func clear(
    _ source: SIMD4<UInt16>,
    pixels: inout MutableSpan<UInt8>
  ) {
    var offset = 0
    while offset + 4 <= pixels.count {
      pixels[offset] = UInt8(source[0])
      pixels[offset + 1] = UInt8(source[1])
      pixels[offset + 2] = UInt8(source[2])
      pixels[offset + 3] = UInt8(source[3])
      offset += 4
    }
  }

  static func composite(
    _ sourceColor: SIMD4<UInt16>,
    spans: [CoverageSpan],
    width: Int,
    pixels: inout MutableSpan<UInt8>
  ) {
    let base = sourceColor
    for span in spans where span.coverage > 0 {
      var offset = (span.y * width + span.x) * 4
      let end = offset + span.length * 4
      let coverage = UInt16(span.coverage)
      let sourceAlpha = (base[3] * coverage + 127) / 255
      let source = SIMD4<UInt16>(
        (base[0] * coverage + 127) / 255,
        (base[1] * coverage + 127) / 255,
        (base[2] * coverage + 127) / 255,
        sourceAlpha
      )
      while offset < end {
        let destination = SIMD4<UInt16>(
          UInt16(pixels[offset]),
          UInt16(pixels[offset + 1]),
          UInt16(pixels[offset + 2]),
          UInt16(pixels[offset + 3])
        )
        let output = sourceOverSIMD(source: source, destination: destination)
        pixels[offset] = UInt8(min(255, output[0]))
        pixels[offset + 1] = UInt8(min(255, output[1]))
        pixels[offset + 2] = UInt8(min(255, output[2]))
        pixels[offset + 3] = UInt8(min(255, output[3]))
        offset += 4
      }
    }
  }

  static func compositeImage(
    source: [UInt8],
    sourceWidth: Int,
    sourceHeight: Int,
    sourceBytesPerRow: Int,
    sourceFormat: RasterPixelFormat,
    inverseTransform: RasterAffineTransform,
    interpolation: RasterInterpolation,
    spans: [CoverageSpan],
    destinationWidth: Int,
    pixels: inout MutableSpan<UInt8>
  ) {
    for span in spans where span.coverage > 0 {
      var destinationOffset = (span.y * destinationWidth + span.x) * 4
      for x in span.x..<(span.x + span.length) {
        let sourcePoint = inverseTransform.transform(RasterPoint(x: Double(x) + 0.5, y: Double(span.y) + 0.5))
        let sample = sample(
          source,
          width: sourceWidth,
          height: sourceHeight,
          bytesPerRow: sourceBytesPerRow,
          format: sourceFormat,
          x: sourcePoint.x,
          y: sourcePoint.y,
          interpolation: interpolation
        )
        composite(
          source: sample,
          coverage: UInt16(span.coverage),
          destinationOffset: destinationOffset,
          pixels: &pixels
        )
        destinationOffset += 4
      }
    }
  }

  static func premultiplied(_ color: RasterColor) throws(RasterError) -> SIMD4<UInt16> {
    guard color.red.isFinite,
      color.green.isFinite,
      color.blue.isFinite,
      color.alpha.isFinite
    else { throw .invalidGeometry }
    let alpha = UInt16((min(1, max(0, color.alpha)) * 255).rounded())
    return SIMD4(
      UInt16((min(1, max(0, color.red)) * Double(alpha)).rounded()),
      UInt16((min(1, max(0, color.green)) * Double(alpha)).rounded()),
      UInt16((min(1, max(0, color.blue)) * Double(alpha)).rounded()),
      alpha
    )
  }

  private static func sample(
    _ bytes: [UInt8],
    width: Int,
    height: Int,
    bytesPerRow: Int,
    format: RasterPixelFormat,
    x: Double,
    y: Double,
    interpolation: RasterInterpolation
  ) -> SIMD4<UInt16> {
    switch interpolation {
    case .nearest:
      return pixel(
        bytes,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        format: format,
        x: Int(floor(x)),
        y: Int(floor(y))
      )
    case .linear:
      let sampleX = x - 0.5
      let sampleY = y - 0.5
      let x0 = Int(floor(sampleX))
      let y0 = Int(floor(sampleY))
      let fractionX = max(0, min(1, sampleX - Double(x0)))
      let fractionY = max(0, min(1, sampleY - Double(y0)))
      let p00 = pixel(bytes, width: width, height: height, bytesPerRow: bytesPerRow, format: format, x: x0, y: y0)
      let p10 = pixel(bytes, width: width, height: height, bytesPerRow: bytesPerRow, format: format, x: x0 + 1, y: y0)
      let p01 = pixel(bytes, width: width, height: height, bytesPerRow: bytesPerRow, format: format, x: x0, y: y0 + 1)
      let p11 = pixel(bytes, width: width, height: height, bytesPerRow: bytesPerRow, format: format, x: x0 + 1, y: y0 + 1)
      var result = SIMD4<UInt16>()
      for component in 0..<4 {
        let top = Double(p00[component]) * (1 - fractionX) + Double(p10[component]) * fractionX
        let bottom = Double(p01[component]) * (1 - fractionX) + Double(p11[component]) * fractionX
        result[component] = UInt16((top * (1 - fractionY) + bottom * fractionY).rounded())
      }
      return result
    }
  }

  private static func pixel(
    _ bytes: [UInt8],
    width: Int,
    height: Int,
    bytesPerRow: Int,
    format: RasterPixelFormat,
    x: Int,
    y: Int
  ) -> SIMD4<UInt16> {
    guard x >= 0, y >= 0, x < width, y < height else { return .zero }
    let offset = y * bytesPerRow + x * 4
    let alpha = UInt16(bytes[offset + 3])
    if format == .rgba8UnormPremultiplied {
      return SIMD4(UInt16(bytes[offset]), UInt16(bytes[offset + 1]), UInt16(bytes[offset + 2]), alpha)
    }
    return SIMD4(
      (UInt16(bytes[offset]) * alpha + 127) / 255,
      (UInt16(bytes[offset + 1]) * alpha + 127) / 255,
      (UInt16(bytes[offset + 2]) * alpha + 127) / 255,
      alpha
    )
  }

  private static func composite(
    source: SIMD4<UInt16>,
    coverage: UInt16,
    destinationOffset: Int,
    pixels: inout MutableSpan<UInt8>
  ) {
    let covered = (source &* SIMD4(repeating: coverage) &+ SIMD4(repeating: 127))
      / SIMD4(repeating: 255)
    let destination = SIMD4<UInt16>(
      UInt16(pixels[destinationOffset]),
      UInt16(pixels[destinationOffset + 1]),
      UInt16(pixels[destinationOffset + 2]),
      UInt16(pixels[destinationOffset + 3])
    )
    let output = sourceOverSIMD(source: covered, destination: destination)
    pixels[destinationOffset] = UInt8(min(255, output[0]))
    pixels[destinationOffset + 1] = UInt8(min(255, output[1]))
    pixels[destinationOffset + 2] = UInt8(min(255, output[2]))
    pixels[destinationOffset + 3] = UInt8(min(255, output[3]))
  }

  static func sourceOverSIMD(
    source: SIMD4<UInt16>,
    destination: SIMD4<UInt16>
  ) -> SIMD4<UInt16> {
    let inverseAlpha = 255 - source[3]
    let retained = (destination &* SIMD4(repeating: inverseAlpha) &+ SIMD4(repeating: 127))
      / SIMD4(repeating: 255)
    return source &+ retained
  }

  static func sourceOverScalar(
    source: SIMD4<UInt16>,
    destination: SIMD4<UInt16>
  ) -> SIMD4<UInt16> {
    let inverseAlpha = 255 - source[3]
    return SIMD4(
      source[0] + (destination[0] * inverseAlpha + 127) / 255,
      source[1] + (destination[1] * inverseAlpha + 127) / 255,
      source[2] + (destination[2] * inverseAlpha + 127) / 255,
      source[3] + (destination[3] * inverseAlpha + 127) / 255
    )
  }
}
