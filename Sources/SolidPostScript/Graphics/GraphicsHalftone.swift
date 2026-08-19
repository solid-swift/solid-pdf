import Foundation

/// A portable compiled PostScript halftone request.
public indirect enum GraphicsHalftone: Sendable, Hashable {
  /// A continuous-tone device retains the requested screen without applying it.
  case continuous
  /// A sampled spot-function screen.
  case spot(GraphicsSpotScreen)
  /// A rectangular threshold array.
  case threshold(GraphicsThresholdScreen)
  /// Per-colorant screens with a mandatory `Default` fallback.
  case colorants([String: GraphicsHalftone])
}
