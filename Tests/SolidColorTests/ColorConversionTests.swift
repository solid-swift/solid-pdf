import SolidColor
import Testing

@Suite struct ColorConversionTests {
  @Test func matrixInverseRoundTripsXYZ() throws {
    let matrix = try ColorMatrix3x3([1, 2, 3, 0, 1, 4, 5, 6, 0])
    let value = ColorXYZ(x: 0.2, y: 0.4, z: 0.6)
    let transformed = matrix.transform(value)
    let restored = try #require(matrix.inverted).transform(transformed)
    #expect(abs(restored.x - value.x) < 1e-12)
    #expect(abs(restored.y - value.y) < 1e-12)
    #expect(abs(restored.z - value.z) < 1e-12)
  }

  @Test func lookupTableInterpolatesAllDimensions() throws {
    let table = try ColorLookupTable(
      dimensions: [2, 2],
      outputComponentCount: 1,
      values: [0, 1, 1, 2]
    )
    #expect(try table.interpolate([0.25, 0.5]) == [0.75])
  }

  @Test func labReferenceWhiteConvertsToReferenceXYZ() {
    let xyz = ColorLab(lightness: 100, a: 0, b: 0).xyz()
    #expect(abs(xyz.x - ColorXYZ.d65.x) < 1e-9)
    #expect(abs(xyz.y - ColorXYZ.d65.y) < 1e-9)
    #expect(abs(xyz.z - ColorXYZ.d65.z) < 1e-9)
  }

  @Test func srgbConverterMapsWhitePointNearWhite() throws {
    let rgb = try NativeColorConverter().rgb(from: .d65)
    #expect(abs(rgb.red - 1) < 0.000_01)
    #expect(abs(rgb.green - 1) < 0.000_01)
    #expect(abs(rgb.blue - 1) < 0.000_01)
  }
}
