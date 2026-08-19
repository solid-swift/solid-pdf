import Foundation

/// Creates render-scoped programs for an output device's trapping implementation.
public protocol GraphicsTrappingEngine<Session>: Sendable {
  associatedtype Session: GraphicsTrappingSession

  /// Creates a trapping session for one render and device.
  func makeSession(for device: GraphicsDeviceDescriptor) throws -> sending Session
}

/// Resolves portable PostScript trapping state into a renderer-specific program.
public protocol GraphicsTrappingSession<ResolvedProgram>: AnyObject {
  associatedtype ResolvedProgram: Sendable

  /// Resolves the current trapping state for `device`.
  func resolve(
    _ state: GraphicsTrappingSnapshot,
    for device: GraphicsDeviceDescriptor
  ) throws -> ResolvedProgram
}

/// A portable trapping engine used by semantic and compatibility targets.
public struct SemanticGraphicsTrappingEngine: GraphicsTrappingEngine, Sendable {
  /// Creates a semantic trapping engine.
  public init() {}

  /// Creates a render-scoped semantic session.
  public func makeSession(
    for device: GraphicsDeviceDescriptor
  ) -> sending SemanticGraphicsTrappingSession {
    SemanticGraphicsTrappingSession()
  }
}

/// A trapping session that preserves portable state without device realization.
public final class SemanticGraphicsTrappingSession: GraphicsTrappingSession, Sendable {
  /// Creates a semantic trapping session.
  public init() {}

  /// Returns the portable state unchanged.
  public func resolve(
    _ state: GraphicsTrappingSnapshot,
    for device: GraphicsDeviceDescriptor
  ) -> GraphicsTrappingSnapshot {
    state
  }
}
