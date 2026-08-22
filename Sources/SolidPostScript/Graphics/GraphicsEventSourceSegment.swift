import Foundation

/// One absolute byte interval within a source resource.
public struct GraphicsEventSourceSegment: Sendable, Hashable {
  /// The resource containing this byte interval.
  public let resourceIdentifier: GraphicsResourceIdentifier
  /// The zero-based byte offset within the resource.
  public let offset: Int64
  /// The nonnegative number of source bytes.
  public let length: Int64

  /// Creates a source byte segment.
  public init(resourceIdentifier: GraphicsResourceIdentifier, offset: Int64, length: Int64) {
    self.resourceIdentifier = resourceIdentifier
    self.offset = offset
    self.length = length
  }
}
