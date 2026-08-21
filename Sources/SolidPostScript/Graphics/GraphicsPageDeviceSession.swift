import Foundation

/// Render-scoped page-device negotiation state.
public protocol GraphicsPageDeviceSession: AnyObject, Sendable {
  /// The settings active when the render begins.
  var initialConfiguration: GraphicsPageDeviceConfiguration { get }
  /// The target's supported geometry and resource limits.
  var capabilities: GraphicsPageDeviceCapabilities { get }
  /// The output devices selectable during this render.
  var outputDeviceProfiles: [GraphicsOutputDeviceProfile] { get }
  /// Negotiates a complete requested configuration.
  func negotiate(_ request: GraphicsPageDeviceRequest) throws -> GraphicsPageDeviceNegotiation
}

extension GraphicsPageDeviceSession {
  /// A source-compatible profile derived from the initial configuration.
  public var outputDeviceProfiles: [GraphicsOutputDeviceProfile] {
    let configuration = initialConfiguration
    return [GraphicsOutputDeviceProfile(
      identifier: configuration.outputDeviceIdentifier,
      resourceName: configuration.outputDevice ?? configuration.name,
      pageDeviceName: configuration.name,
      inputMedia: configuration.inputMedia,
      outputDestinations: configuration.outputDestinations,
      physicalCapabilities: capabilities.physical
    )]
  }
}
