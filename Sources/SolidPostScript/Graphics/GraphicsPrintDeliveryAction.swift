import Foundation

/// An ordered physical delivery action retained for a future printer adapter.
public struct GraphicsPrintDeliveryAction: Sendable, Hashable {
  /// The physical operation to perform.
  public enum Kind: Sendable, Hashable {
    /// Advance roll media by the specified default-user-space distance.
    case advance(distance: Double)
    /// Cut roll media.
    case cut
    /// Jog the output stack.
    case jog
  }

  /// The boundary that scheduled an action.
  public enum Boundary: Sendable, Hashable {
    /// A successful page transmission.
    case pageTransmission
    /// Completion of one page set.
    case pageSet
    /// Page-device deactivation.
    case deviceDeactivation
    /// Normal job completion.
    case jobCompletion
  }

  /// Zero-based position in the action stream.
  public let ordinal: Int
  /// The requested operation.
  public let kind: Kind
  /// The lifecycle boundary at which it occurs.
  public let boundary: Boundary

  /// Creates a delivery action.
  public init(ordinal: Int, kind: Kind, boundary: Boundary) {
    self.ordinal = ordinal
    self.kind = kind
    self.boundary = boundary
  }
}
