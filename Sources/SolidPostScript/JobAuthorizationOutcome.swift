//
//  JobAuthorizationOutcome.swift
//

import Foundation

/// The privilege granted to a PostScript job-lifecycle transition.
public enum JobAuthorizationOutcome: Equatable, Sendable {
  /// The requested transition is not authorized.
  case denied
  /// The requested transition starts an ordinary job.
  case ordinary
  /// The requested transition starts a system-administrator job.
  case administrator
}
