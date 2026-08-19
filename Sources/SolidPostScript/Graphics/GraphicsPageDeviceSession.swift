import Foundation

/// Render-scoped page-device negotiation state.
public protocol GraphicsPageDeviceSession: AnyObject, Sendable {
  /// The settings active when the render begins.
  var initialConfiguration: GraphicsPageDeviceConfiguration { get }
  /// The target's supported geometry and resource limits.
  var capabilities: GraphicsPageDeviceCapabilities { get }
  /// Negotiates a complete requested configuration.
  func negotiate(_ request: GraphicsPageDeviceRequest) throws -> GraphicsPageDeviceNegotiation
}
