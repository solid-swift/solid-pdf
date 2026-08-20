import Foundation

/// The result of physical media selection.
public enum GraphicsMediaSelection: Sendable, Hashable {
  /// No physical source is involved.
  case virtual
  /// A physical source was selected immediately.
  case selected(GraphicsMediaSource)
  /// Selection was deferred with the normalized request intact.
  case deferred(GraphicsMediaRequest)
}
