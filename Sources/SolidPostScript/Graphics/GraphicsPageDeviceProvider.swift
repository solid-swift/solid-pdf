import Foundation

/// Creates typed, render-scoped page-device negotiation state for a graphics target.
public protocol GraphicsPageDeviceProvider<Session>: Sendable {
  associatedtype Session: GraphicsPageDeviceSession

  /// Creates the page-device session for one render.
  func makeSession(for descriptor: GraphicsDeviceDescriptor) throws -> sending Session
}
