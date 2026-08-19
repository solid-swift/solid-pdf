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

  /// The deterministic installation-default 8-by-8 threshold screen.
  public static let `default`: Self = .threshold(try! GraphicsThresholdScreen(
    width: 8,
    height: 8,
    thresholds: [
      1, 129, 33, 161, 9, 137, 41, 169,
      193, 65, 225, 97, 201, 73, 233, 105,
      49, 177, 17, 145, 57, 185, 25, 153,
      241, 113, 209, 81, 249, 121, 217, 89,
      13, 141, 45, 173, 5, 133, 37, 165,
      205, 77, 237, 109, 197, 69, 229, 101,
      61, 189, 29, 157, 53, 181, 21, 149,
      253, 125, 221, 93, 245, 117, 213, 85,
    ]
  ))
}
