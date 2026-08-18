@testable import SolidRaster
import Testing

@Suite struct RasterCompositorTests {
  @Test(arguments: [UInt16(0), 1, 64, 127, 128, 254, 255])
  func scalarAndSIMDKernelsAgree(_ alpha: UInt16) {
    for red in stride(from: UInt16(0), through: 255, by: 17) {
      let source = SIMD4<UInt16>(red, 11, min(alpha, 193), alpha)
      let destination = SIMD4<UInt16>(73, 149, 231, 255)
      #expect(
        RasterCompositor.sourceOverSIMD(source: source, destination: destination)
          == RasterCompositor.sourceOverScalar(source: source, destination: destination)
      )
    }
  }
}
