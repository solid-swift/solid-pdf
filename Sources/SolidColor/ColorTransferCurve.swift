import Foundation

/// A deterministic one-dimensional color transfer curve.
public enum ColorTransferCurve: Sendable, Hashable {
  /// Leaves the component unchanged.
  case linear
  /// Raises a nonnegative component to `gamma`.
  case gamma(Double)
  /// Applies the IEC 61966-2-1 sRGB encoding transfer function.
  case sRGB
  /// Linearly interpolates a uniformly sampled table over zero through one.
  case table([Double])

  /// Evaluates the transfer curve.
  public func evaluate(_ component: Double) throws(ColorError) -> Double {
    guard component.isFinite else { throw .invalidValue }
    switch self {
    case .linear:
      return component
    case .gamma(let gamma):
      guard gamma.isFinite, gamma > 0 else { throw .invalidValue }
      return pow(max(0, component), gamma)
    case .sRGB:
      let value = max(0, component)
      return value <= 0.003_130_8
        ? 12.92 * value
        : 1.055 * pow(value, 1 / 2.4) - 0.055
    case .table(let values):
      guard !values.isEmpty, values.allSatisfy(\.isFinite) else { throw .invalidValue }
      guard values.count > 1 else { return values[0] }
      let position = component.clampedUnit * Double(values.count - 1)
      let lower = Int(position.rounded(.down))
      let upper = min(values.count - 1, lower + 1)
      let fraction = position - Double(lower)
      return values[lower] + (values[upper] - values[lower]) * fraction
    }
  }
}
