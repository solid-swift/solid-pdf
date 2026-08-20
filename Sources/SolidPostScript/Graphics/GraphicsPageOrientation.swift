import Foundation

/// Rotation of a page image relative to the medium's default orientation.
public enum GraphicsPageOrientation: Int, Sendable, Hashable, CaseIterable {
  /// The default orientation.
  case defaultOrientation = 0
  /// A 90-degree counterclockwise rotation.
  case counterclockwise90 = 1
  /// A 180-degree rotation.
  case rotated180 = 2
  /// A 270-degree counterclockwise rotation.
  case counterclockwise270 = 3
}
