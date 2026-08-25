import Foundation

/// Format-neutral source provenance attached to a semantic graphics event.
public struct GraphicsEventOrigin: Sendable, Hashable {
  /// The semantic resource whose execution produced the event, when known.
  public let resourceIdentifier: GraphicsResourceIdentifier?
  /// Ordered byte segments contributing to the source operation.
  public let byteSegments: [GraphicsEventSourceSegment]

  /// Creates event provenance from an optional resource and ordered byte segments.
  public init(
    resourceIdentifier: GraphicsResourceIdentifier? = nil,
    byteSegments: [GraphicsEventSourceSegment] = []
  ) {
    self.resourceIdentifier = resourceIdentifier
    self.byteSegments = byteSegments
  }
}
