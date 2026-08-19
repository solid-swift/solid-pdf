/// An immutable stitching function corresponding to PostScript FunctionType 3.
public struct ColorStitchingFunction: Sendable, Hashable {
  /// The inclusive one-dimensional input domain.
  public let domain: ColorComponentRange
  /// Optional output ranges.
  public let range: [ColorComponentRange]?
  /// The functions selected by successive intervals.
  public let functions: [ColorFunction]
  /// Interior interval boundaries.
  public let bounds: [Double]
  /// Per-function encoded domains.
  public let encode: [Double]

  /// The number of function inputs.
  public let inputCount = 1
  /// The number of function outputs.
  public var outputCount: Int { functions[0].outputCount }

  /// Creates and validates a stitching function.
  public init(
    domain: ColorComponentRange,
    range: [ColorComponentRange]? = nil,
    functions: [ColorFunction],
    bounds: [Double],
    encode: [Double]
  ) throws(ColorError) {
    guard domain.lowerBound < domain.upperBound, !functions.isEmpty, functions.count <= 65_536,
      functions.allSatisfy({ $0.inputCount == 1 }),
      functions.allSatisfy({ $0.outputCount == functions[0].outputCount }),
      range == nil || range?.count == functions[0].outputCount,
      bounds.count == functions.count - 1, encode.count == functions.count * 2,
      encode.allSatisfy(\.isFinite)
    else { throw .invalidDomain }
    var prior = domain.lowerBound
    for boundary in bounds {
      guard boundary > prior, boundary < domain.upperBound else { throw .invalidDomain }
      prior = boundary
    }
    self.domain = domain
    self.range = range
    self.functions = functions
    self.bounds = bounds
    self.encode = encode
  }

  /// Evaluates the selected subfunction.
  public func evaluate(_ input: [Double]) throws(ColorError) -> [Double] {
    guard input.count == 1, input[0].isFinite else { throw .componentCount }
    let value = domain.clamp(input[0])
    let index = bounds.firstIndex(where: { value < $0 }) ?? functions.count - 1
    let lower = index == 0 ? domain.lowerBound : bounds[index - 1]
    let upper = index == functions.count - 1 ? domain.upperBound : bounds[index]
    let fraction = upper == lower ? 0 : (value - lower) / (upper - lower)
    let encoded = encode[index * 2] + fraction * (encode[index * 2 + 1] - encode[index * 2])
    let result = try functions[index].evaluate([encoded])
    return result.indices.map { range?[$0].clamp(result[$0]) ?? result[$0] }
  }
}
