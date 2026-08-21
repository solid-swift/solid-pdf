import Foundation

/// A successful graphics operation and its authoritative state transition.
public struct GraphicsEvent: Sendable, Hashable {
  /// The validated operation preserving the originating PostScript intent.
  public let operation: GraphicsOperation
  /// The graphics state immediately before the operation.
  public let before: GraphicsStateSnapshot
  /// The graphics state immediately after the operation.
  public let after: GraphicsStateSnapshot

  /// Creates a graphics event.
  public init(operation: GraphicsOperation, before: GraphicsStateSnapshot, after: GraphicsStateSnapshot) {
    self.operation = operation
    self.before = before
    self.after = after
  }
}
