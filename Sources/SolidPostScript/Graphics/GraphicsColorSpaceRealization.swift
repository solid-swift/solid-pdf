import Foundation

/// Immutable target-facing data sufficient to reproduce a selected color space.
public struct GraphicsColorSpaceRealization: Sendable, Hashable {
  /// Inclusive component ranges in source order.
  public let componentRanges: [ClosedRange<Double>]
  /// Indexed lookup bytes, when the source is an Indexed color space.
  public let indexedLookup: Data?
  /// The alternative space used by named colors, when applicable.
  public let alternativeSpace: GraphicsColorSpaceDescription?
  /// A bounded sampled transform from source components into the alternative space.
  public let sampledTransform: GraphicsSampledColorTransform?

  /// Creates a color-space realization.
  public init(
    componentRanges: [ClosedRange<Double>],
    indexedLookup: Data? = nil,
    alternativeSpace: GraphicsColorSpaceDescription? = nil,
    sampledTransform: GraphicsSampledColorTransform? = nil
  ) {
    self.componentRanges = componentRanges
    self.indexedLookup = indexedLookup
    self.alternativeSpace = alternativeSpace
    self.sampledTransform = sampledTransform
  }
}
