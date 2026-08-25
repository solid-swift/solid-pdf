import Foundation

/// A successful graphics operation and its authoritative state transition.
public struct GraphicsEvent: Sendable, Hashable {
  /// The validated operation preserving the originating PostScript intent.
  public let operation: GraphicsOperation
  /// The graphics state immediately before the operation.
  public let before: GraphicsStateSnapshot
  /// The graphics state immediately after the operation.
  public let after: GraphicsStateSnapshot
  /// Optional source provenance for the operation.
  public let origin: GraphicsEventOrigin?
  /// Active marked-content scopes in outer-to-inner order.
  public let markedContentPath: [GraphicsMarkedContentScope]
  /// Visibility resolved for this operation.
  public let visibility: GraphicsContentVisibility

  /// Creates a graphics event.
  public init(
    operation: GraphicsOperation,
    before: GraphicsStateSnapshot,
    after: GraphicsStateSnapshot,
    origin: GraphicsEventOrigin? = nil,
    markedContentPath: [GraphicsMarkedContentScope] = [],
    visibility: GraphicsContentVisibility = .visible
  ) {
    self.operation = operation
    self.before = before
    self.after = after
    self.origin = origin
    self.markedContentPath = markedContentPath
    self.visibility = visibility
  }
}
