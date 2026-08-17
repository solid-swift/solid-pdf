//
//  InterpreterLifecycleObserver.swift
//

import Foundation

/// A notification emitted by an interpreter session lifecycle.
public enum InterpreterLifecycleEvent: Sendable {
  case started
  case jobStarted(persistent: Bool)
  case jobFinished(persistent: Bool)
  case exitServerAuthorized
  case error(String)
}

/// Observes interpreter lifecycle events without controlling their outcome.
public protocol InterpreterLifecycleObserver: Sendable {

  /// Receives a lifecycle event.
  func interpreter(didEmit event: InterpreterLifecycleEvent) async

  /// Returns an optional notice to write through the interpreter's standard-output channel.
  func notice(for event: InterpreterLifecycleEvent) async -> Data?
}

extension InterpreterLifecycleObserver {

  /// Produces no language-visible notice by default.
  public func notice(for event: InterpreterLifecycleEvent) async -> Data? { nil }
}

/// An interpreter lifecycle observer that ignores all events.
public struct NoInterpreterLifecycleObserver: InterpreterLifecycleObserver {

  /// Creates an instance.
  public init() {}

  /// Ignores the event.
  public func interpreter(didEmit event: InterpreterLifecycleEvent) async {}
}
