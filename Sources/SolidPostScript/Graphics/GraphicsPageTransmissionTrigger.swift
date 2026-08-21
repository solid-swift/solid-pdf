import Foundation

/// The language or lifecycle action that requested page transmission.
public enum GraphicsPageTransmissionTrigger: Sendable, Hashable {
  /// A `showpage` operation.
  case showPage
  /// A `copypage` operation.
  case copyPage
  /// Page-device deactivation after EndPage returned true.
  case deviceDeactivation
}
