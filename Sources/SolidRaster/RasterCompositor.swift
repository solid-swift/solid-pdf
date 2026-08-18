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
      let inverseAlpha = 255 - sourceAlpha
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
        let scaled = destination &* SIMD4<UInt16>(repeating: inverseAlpha)
        let rounded = scaled &+ SIMD4<UInt16>(repeating: 127)
        let retained = rounded / SIMD4<UInt16>(repeating: 255)
        let output = source &+ retained
        pixels[offset] = UInt8(min(255, output[0]))
        pixels[offset + 1] = UInt8(min(255, output[1]))
        pixels[offset + 2] = UInt8(min(255, output[2]))
        pixels[offset + 3] = UInt8(min(255, output[3]))
        offset += 4
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
}
