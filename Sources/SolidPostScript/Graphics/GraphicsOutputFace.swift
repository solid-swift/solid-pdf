import Foundation

/// The stacking direction used by an output destination.
public enum GraphicsOutputFace: Sendable, Hashable {
  /// Stack output in normal reading order.
  case faceDown
  /// Stack output in reverse reading order.
  case faceUp
}
