import Foundation

/// Creates target-specific device-rendering state for one render.
public protocol GraphicsDeviceRenderingEngine<Session>: Sendable {
  associatedtype Session: GraphicsDeviceRenderingSession

  /// Creates isolated device-rendering state for `device`.
  func makeSession(for device: GraphicsDeviceDescriptor) throws -> sending Session
}

/// Resolves portable transfer and halftone state into a target-specific program.
public protocol GraphicsDeviceRenderingSession<ResolvedProgram>: AnyObject {
  associatedtype ResolvedProgram: Sendable

  /// Resolves rendering state for one device configuration.
  func resolve(
    _ state: GraphicsDeviceRenderingSnapshot,
    for device: GraphicsDeviceDescriptor
  ) throws -> ResolvedProgram
}

/// The compatibility engine that preserves portable rendering state unchanged.
public struct SemanticGraphicsDeviceRenderingEngine: GraphicsDeviceRenderingEngine, Sendable {
  /// Creates a semantic device-rendering engine.
  public init() {}

  /// Creates a semantic render-scoped session.
  public func makeSession(
    for device: GraphicsDeviceDescriptor
  ) -> sending SemanticGraphicsDeviceRenderingSession {
    SemanticGraphicsDeviceRenderingSession()
  }
}

/// A session used by recording, null, and source-compatible custom targets.
public final class SemanticGraphicsDeviceRenderingSession: GraphicsDeviceRenderingSession {
  /// Creates a semantic session.
  public init() {}

  /// Returns the portable rendering state unchanged.
  public func resolve(
    _ state: GraphicsDeviceRenderingSnapshot,
    for device: GraphicsDeviceDescriptor
  ) -> GraphicsDeviceRenderingSnapshot {
    state
  }
}
