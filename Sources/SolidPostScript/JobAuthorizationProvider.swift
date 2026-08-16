//
//  JobAuthorizationProvider.swift
//

import Foundation

/// A request to authorize a PostScript job-lifecycle transition.
public struct JobAuthorizationRequest: Sendable {

  /// The operation requesting authorization.
  public enum Purpose: Sendable {
    case startJob
    case exitServer
  }

  /// The operation requesting authorization.
  public let purpose: Purpose
  /// The password supplied by the PostScript program.
  public let candidate: Data
  /// Whether the requested job may persistently modify initial VM.
  public let persistent: Bool

  /// Creates an authorization request.
  public init(purpose: Purpose, candidate: Data, persistent: Bool) {
    self.purpose = purpose
    self.candidate = candidate
    self.persistent = persistent
  }
}

/// Authorizes PostScript job-lifecycle transitions.
public protocol JobAuthorizationProvider: Sendable {

  /// Returns whether the requested transition is authorized.
  func authorize(_ request: JobAuthorizationRequest) async throws -> Bool
}
