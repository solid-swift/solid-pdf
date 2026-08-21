#if canImport(CoreGraphics)
import Foundation
import SolidPostScript

/// Preserves portable rendering controls for Core Graphics or its raster fallback.
public struct CoreGraphicsDeviceRenderingEngine: GraphicsDeviceRenderingEngine, Sendable {
  /// Creates a Core Graphics device-rendering engine.
  public init() {}

  /// Creates one Core Graphics render-scoped session.
  public func makeSession(
    for device: GraphicsDeviceDescriptor
  ) -> sending CoreGraphicsDeviceRenderingSession {
    CoreGraphicsDeviceRenderingSession()
  }
}

/// Determines whether Core Graphics can realize a rendering state directly.
public final class CoreGraphicsDeviceRenderingSession: GraphicsDeviceRenderingSession {
  /// Creates a Core Graphics rendering session.
  public init() {}

  /// Returns portable state for direct-path or fallback selection by the renderer.
  public func resolve(
    _ state: GraphicsDeviceRenderingSnapshot,
    for device: GraphicsDeviceDescriptor
  ) -> GraphicsDeviceRenderingSnapshot {
    state
  }
}
#endif
