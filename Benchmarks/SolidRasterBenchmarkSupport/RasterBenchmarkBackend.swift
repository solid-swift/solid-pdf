import Foundation

/// A raster implementation selectable by the renderer comparison benchmark.
public enum RasterBenchmarkBackend: String, CaseIterable, Sendable {
  /// The native Swift rasterizer.
  case native
  /// The vendored PlutoVG rasterizer.
  case plutovg

  /// The environment variable used to select a comparison backend.
  public static let environmentVariable = "SOLIDPDF_RASTER_BENCHMARK_BACKEND"

  /// Resolves a backend from an optional environment value.
  public init(environmentValue: String?) throws {
    guard let environmentValue, !environmentValue.isEmpty else {
      self = .native
      return
    }
    guard let backend = Self(rawValue: environmentValue.lowercased()) else {
      throw SelectionError.unknownBackend(environmentValue)
    }
    self = backend
  }

  /// Resolves a backend from the process environment.
  public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
    try Self(environmentValue: environment[environmentVariable])
  }

  /// A backend-selection failure raised before benchmark registration.
  public enum SelectionError: Error, Equatable, Sendable {
    /// The supplied backend name is not registered.
    case unknownBackend(String)
  }
}
