import Foundation

/// One device-space path region and its captured trapping parameters.
public struct GraphicsTrappingZone: Sendable, Hashable {
  /// The winding-filled device-space boundary of the zone.
  public let path: GraphicsPath
  /// The parameters captured when the zone was established.
  public let parameters: GraphicsTrappingParameters
  /// The monotonic creation order used to resolve overlapping zones.
  public let sequence: Int

  /// Creates a trapping zone.
  public init(path: GraphicsPath, parameters: GraphicsTrappingParameters, sequence: Int) {
    self.path = path
    self.parameters = parameters
    self.sequence = sequence
  }
}
