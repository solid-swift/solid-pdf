//
//  JobAuthorizationOutcomeProvider.swift
//

import Foundation

/// Authorizes PostScript job transitions with an explicit job privilege.
public protocol JobAuthorizationOutcomeProvider: JobAuthorizationProvider {
  /// Returns the privilege granted to the requested transition.
  func authorizationOutcome(for request: JobAuthorizationRequest) async throws -> JobAuthorizationOutcome
}

extension JobAuthorizationOutcomeProvider {
  /// Returns whether the requested transition is authorized.
  public func authorize(_ request: JobAuthorizationRequest) async throws -> Bool {
    try await authorizationOutcome(for: request) != .denied
  }
}
