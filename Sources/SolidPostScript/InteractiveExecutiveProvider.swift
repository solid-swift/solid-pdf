//
//  InteractiveExecutiveProvider.swift
//

import Foundation

/// An event supplied to the PostScript interactive executive.
public enum InteractiveExecutiveEvent: Sendable {
  case data(Data)
  case interrupt
  case endOfFile
}

/// Supplies input events to the PostScript interactive executive.
public protocol InteractiveExecutiveProvider: Sendable {

  /// Returns the next input event.
  func nextEvent() async throws -> InteractiveExecutiveEvent
}
