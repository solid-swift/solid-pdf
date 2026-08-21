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

  @Test func sampledFunctionUsesLowerEncodeEndpointForZeroWidthDomain() throws {
    let function = try ColorSampledFunction(
      domain: [ColorComponentRange(0.5, 0.5)],
      range: [ColorComponentRange(0.25, 0.25)],
      size: [2],
      bitsPerSample: 8,
      encode: [1, 0],
      sampleData: Data([0, 255])
    )

    #expect(try function.evaluate([-1]) == [0.25])
    #expect(try function.evaluate([1]) == [0.25])
  }

  @Test func sampledFunctionFallsBackToLinearWhenAnyCubicDimensionIsTooSmall() throws {
    let function = try ColorSampledFunction(
      domain: [ColorComponentRange(0, 1), ColorComponentRange(0, 1)],
      range: [ColorComponentRange(0, 1)],
      size: [4, 2],
      bitsPerSample: 8,
      order: 3,
      sampleData: Data([0, 0, 0, 0, 255, 255, 255, 255])
    )

    #expect(abs(try function.evaluate([0.5, 0.25])[0] - 0.25) < 1e-12)
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

  @Test func exponentialAndStitchingFunctionsAcceptZeroWidthDomains() throws {
    let exponential = try ColorExponentialFunction(
      domain: ColorComponentRange(0.5, 0.5),
      c0: [0],
      c1: [1],
      exponent: 2
    )
    #expect(try exponential.evaluate([0]) == [0.25])

    let stitching = try ColorStitchingFunction(
      domain: ColorComponentRange(2, 2),
      functions: [.exponential(exponential)],
      bounds: [],
      encode: [0.25, 0.75]
    )
    #expect(try stitching.evaluate([10]) == [0.25])
    #expect(throws: ColorError.invalidDomain) {
      try ColorStitchingFunction(
        domain: ColorComponentRange(2, 2),
        functions: [.exponential(exponential), .exponential(exponential)],
        bounds: [2],
        encode: [0, 1, 0, 1]
      )
    }
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
