import Foundation

/// An immutable exponential interpolation function corresponding to PostScript FunctionType 2.
public struct ColorExponentialFunction: Sendable, Hashable {
  /// The inclusive one-dimensional input domain.
  public let domain: ColorComponentRange
  /// Optional output ranges.
  public let range: [ColorComponentRange]?
  /// Values at zero.
  public let c0: [Double]
  /// Values at one.
  public let c1: [Double]
  /// The interpolation exponent.
  public let exponent: Double

  /// The number of function inputs.
  public let inputCount = 1
  /// The number of function outputs.
  public var outputCount: Int { c0.count }

  /// Creates and validates an exponential function.
  public init(
    domain: ColorComponentRange,
    range: [ColorComponentRange]? = nil,
    c0: [Double] = [0],
    c1: [Double] = [1],
    exponent: Double
  ) throws(ColorError) {
    guard domain.lowerBound < domain.upperBound, (1...16).contains(c0.count), c0.count == c1.count,
      range == nil || range?.count == c0.count,
      c0.allSatisfy(\.isFinite), c1.allSatisfy(\.isFinite), exponent.isFinite
    else { throw .invalidDomain }
    if exponent.rounded() != exponent, domain.lowerBound < 0 { throw .invalidDomain }
    if exponent < 0, domain.lowerBound <= 0, domain.upperBound >= 0 { throw .invalidDomain }
    self.domain = domain
    self.range = range
    self.c0 = c0
    self.c1 = c1
    self.exponent = exponent
  }

  /// Evaluates the exponential function.
  public func evaluate(_ input: [Double]) throws(ColorError) -> [Double] {
    guard input.count == 1, input[0].isFinite else { throw .componentCount }
    let factor = pow(domain.clamp(input[0]), exponent)
    guard factor.isFinite else { throw .invalidValue }
    return c0.indices.map { index in
      let value = c0[index] + factor * (c1[index] - c0[index])
      return range?[index].clamp(value) ?? value
    }
  }
}
