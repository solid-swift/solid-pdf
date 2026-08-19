import Foundation

/// An immutable sampled one-input, one-output function used by device rendering.
public struct GraphicsComponentFunction: Sendable, Hashable {
  /// Uniform samples spanning the closed input interval `0...1`.
  public let samples: [Double]

  /// Creates a sampled component function.
  ///
  /// At least two finite samples are required. Values are retained without clipping because
  /// black generation and undercolor removal have language-defined intermediate ranges.
  public init(samples: [Double]) throws {
    guard samples.count >= 2, samples.allSatisfy(\.isFinite) else { throw Error.rangeCheck }
    self.samples = samples
  }

  /// The identity component function.
  public static let identity = try! Self(samples: [0, 1])

  /// A function that always returns zero.
  public static let zero = try! Self(samples: [0, 0])

  /// Evaluates the function with linear interpolation.
  public func evaluate(_ input: Double) -> Double {
    let position = min(1, max(0, input)) * Double(samples.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = min(samples.count - 1, lower + 1)
    let fraction = position - Double(lower)
    return samples[lower] + (samples[upper] - samples[lower]) * fraction
  }
}
