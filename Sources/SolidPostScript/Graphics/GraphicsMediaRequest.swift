import Foundation

/// A normalized request for physical input media.
public struct GraphicsMediaRequest: Sendable, Hashable {
  /// The requested media attributes; nil fields mean "don't care."
  public let attributes: GraphicsMediaAttributes
  /// The requested leading edge, if any.
  public let leadingEdge: GraphicsLeadingEdge?
  /// Whether manual feeding is requested.
  public let manualFeed: Bool
  /// The requested source position, if any.
  public let position: Int?
  /// Whether automatic tray switching is requested.
  public let traySwitch: Bool
  /// Whether media selection is deferred to the delivery subsystem.
  public let isDeferred: Bool

  /// Creates a media request.
  public init(
    attributes: GraphicsMediaAttributes = .init(),
    leadingEdge: GraphicsLeadingEdge? = nil,
    manualFeed: Bool = false,
    position: Int? = nil,
    traySwitch: Bool = false,
    isDeferred: Bool = false
  ) {
    self.attributes = attributes
    self.leadingEdge = leadingEdge
    self.manualFeed = manualFeed
    self.position = position
    self.traySwitch = traySwitch
    self.isDeferred = isDeferred
  }
}
