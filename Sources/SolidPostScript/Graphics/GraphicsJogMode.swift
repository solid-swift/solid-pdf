import Foundation

/// When delivered sheets should be physically jogged.
public enum GraphicsJogMode: Int, Sendable, Hashable, CaseIterable {
  /// Never jog output.
  case never = 0
  /// Jog when the page device is deactivated.
  case deviceDeactivation = 1
  /// Jog at normal job completion.
  case jobCompletion = 2
  /// Jog after every page set.
  case pageSet = 3
}
