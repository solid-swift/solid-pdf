//
//  StartupProgramProvider.swift
//

import Foundation

/// Supplies optional PostScript startup content for an interpreter session.
public protocol StartupProgramProvider: Sendable {

  /// Returns the program to execute for `StartupMode`, or `nil` when no program is required.
  func startupProgram(for mode: Int32) async throws -> Data?
}

/// A startup provider that supplies no program.
public struct NoStartupProgramProvider: StartupProgramProvider {

  /// Creates an instance.
  public init() {}

  /// Returns no startup program.
  public func startupProgram(for mode: Int32) async throws -> Data? { nil }
}
