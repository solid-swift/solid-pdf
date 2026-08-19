/// An immutable PostScript color function.
public indirect enum ColorFunction: Sendable, Hashable {
  /// A sampled function (FunctionType 0).
  case sampled(ColorSampledFunction)
  /// An exponential interpolation function (FunctionType 2).
  case exponential(ColorExponentialFunction)
  /// A stitching function (FunctionType 3).
  case stitching(ColorStitchingFunction)

  /// The number of function inputs.
  public var inputCount: Int {
    switch self {
    case .sampled(let function): function.inputCount
    case .exponential(let function): function.inputCount
    case .stitching(let function): function.inputCount
    }
  }

  /// The number of function outputs.
  public var outputCount: Int {
    switch self {
    case .sampled(let function): function.outputCount
    case .exponential(let function): function.outputCount
    case .stitching(let function): function.outputCount
    }
  }

  /// Inclusive input domains in function-input order.
  public var domain: [ColorComponentRange] {
    switch self {
    case .sampled(let function): function.domain
    case .exponential(let function): [function.domain]
    case .stitching(let function): [function.domain]
    }
  }

  /// Evaluates the function after clipping inputs to its domain and outputs to its range.
  public func evaluate(_ input: [Double]) throws(ColorError) -> [Double] {
    switch self {
    case .sampled(let function): try function.evaluate(input)
    case .exponential(let function): try function.evaluate(input)
    case .stitching(let function): try function.evaluate(input)
    }
  }
}
