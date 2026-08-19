import Foundation

/// Describes the number of representable levels in a graphics device's process components.
public enum GraphicsDeviceQuantization: Sendable, Hashable {
  /// Components are rendered without spatial quantization.
  case continuousTone
  /// Each process component is restricted to the corresponding positive number of levels.
  case discrete(levels: [Int])
}
