import Foundation

/// When roll media should be advanced or cut.
public enum GraphicsMediaActionMode: Int, Sendable, Hashable, CaseIterable {
  /// Never perform the action.
  case never = 0
  /// Perform the action when the page device is deactivated.
  case deviceDeactivation = 1
  /// Perform the action at normal job completion.
  case jobCompletion = 2
  /// Perform the action after every page set.
  case pageSet = 3
  /// Perform the action after every page transmission.
  case pageTransmission = 4
}
