import Foundation
import SolidColor
import Testing

@Suite struct ColorFunctionTests {
  @Test func sampledFunctionDecodesPackedBitsAndClips() throws {
    let function = try ColorSampledFunction(
      domain: [ColorComponentRange(0, 1)],
      range: [ColorComponentRange(0, 1)],
      size: [2],
      bitsPerSample: 4,
      sampleData: Data([0x0F])
    )
    #expect(try function.evaluate([-1]) == [0])
    #expect(try function.evaluate([0.5]) == [0.5])
    #expect(try function.evaluate([2]) == [1])
  }

  @Test func sampledFunctionSupportsSizeOneDimensionsAndCubicOrder() throws {
    let function = try ColorSampledFunction(
      domain: [ColorComponentRange(0, 1), ColorComponentRange(0, 1)],
      range: [ColorComponentRange(0, 1)],
      size: [1, 2],
      bitsPerSample: 8,
      order: 3,
      sampleData: Data([64, 192])
    )
    let value = try function.evaluate([0.75, 0.5])[0]
    #expect(value > 0.4 && value < 0.6)
  }

  @Test func sampledFunctionStoresItsFirstInputDimensionFastest() throws {
    let function = try ColorSampledFunction(
      domain: [ColorComponentRange(0, 1), ColorComponentRange(0, 1)],
      range: [ColorComponentRange(0, 1)],
      size: [2, 2],
      bitsPerSample: 8,
      sampleData: Data([0, 64, 128, 255])
    )
    #expect(try function.evaluate([1, 0]) == [64.0 / 255.0])
    #expect(try function.evaluate([0, 1]) == [128.0 / 255.0])
  }

  @Test func exponentialAndStitchingFunctionsEvaluateTheirDomains() throws {
    let first = ColorFunction.exponential(try ColorExponentialFunction(
      domain: ColorComponentRange(0, 1),
      c0: [0],
      c1: [1],
      exponent: 2
    ))
    let second = ColorFunction.exponential(try ColorExponentialFunction(
      domain: ColorComponentRange(0, 1),
      c0: [1],
      c1: [0],
      exponent: 1
    ))
    let stitching = try ColorStitchingFunction(
      domain: ColorComponentRange(0, 2),
      functions: [first, second],
      bounds: [1],
      encode: [0, 1, 0, 1]
    )
    #expect(try stitching.evaluate([0.5]) == [0.25])
    #expect(try stitching.evaluate([1.5]) == [0.5])
  }

  @Test func functionLimitsAreValidated() throws {
    #expect(throws: ColorError.invalidDomain) {
      try ColorStitchingFunction(
        domain: ColorComponentRange(0, 1),
        functions: [],
        bounds: [],
        encode: []
      )
    }
    #expect(throws: ColorError.invalidDomain) {
      try ColorSampledFunction(
        domain: [ColorComponentRange(0, 1)],
        range: [ColorComponentRange(0, 1)],
        size: [2],
        bitsPerSample: 3,
        sampleData: Data([0])
      )
    }
  }
}
