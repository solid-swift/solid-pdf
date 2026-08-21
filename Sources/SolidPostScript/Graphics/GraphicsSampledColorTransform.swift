import Foundation

/// A bounded multidimensional sampled color transform.
public struct GraphicsSampledColorTransform: Sendable, Hashable {
  /// Sample counts in each input dimension.
  public let size: [Int]
  /// Number of output components in each sample.
  public let outputComponentCount: Int
  /// Interleaved normalized 16-bit output samples.
  public let samples: Data

  /// Creates a sampled transform.
  public init(size: [Int], outputComponentCount: Int, samples: Data) {
    self.size = size
    self.outputComponentCount = outputComponentCount
    self.samples = samples
  }
}
