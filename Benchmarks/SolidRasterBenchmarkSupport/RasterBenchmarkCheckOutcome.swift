/// The meaning of a Benchmark baseline-check process status.
public enum RasterBenchmarkCheckOutcome: Equatable, Sendable {
  /// The candidate is within the configured tolerance.
  case withinTolerance
  /// The candidate is a statistically significant improvement.
  case improvement
  /// The candidate exceeds the configured regression threshold.
  case regression
  /// Benchmark could not perform a meaningful comparison.
  case infrastructureFailure(Int32)

  /// Interprets the exit status documented by Benchmark's baseline checker.
  public init(exitStatus: Int32) {
    switch exitStatus {
    case 0: self = .withinTolerance
    case 2: self = .regression
    case 4: self = .improvement
    default: self = .infrastructureFailure(exitStatus)
    }
  }

  /// Interprets a status returned through SwiftPM, which can collapse a plugin's regression status to `1`.
  public init(processExitStatus: Int32, diagnosticOutput: String) {
    if processExitStatus == 1, diagnosticOutput.contains("benchmarkThresholdRegression") {
      self = .regression
    } else {
      self.init(exitStatus: processExitStatus)
    }
  }

  /// Whether the comparison satisfies the raster acceptance gate.
  public var passed: Bool {
    switch self {
    case .withinTolerance, .improvement: true
    case .regression, .infrastructureFailure: false
    }
  }
}
