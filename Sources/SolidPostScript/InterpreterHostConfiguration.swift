//
//  InterpreterHostConfiguration.swift
//

import Foundation
import SolidIO

/// Application-owned streams and policy providers used by an interpreter environment.
public struct InterpreterHostConfiguration: Sendable {

  /// The borrowed standard-input stream.
  public let standardInput: any Source
  /// The borrowed standard-output stream.
  public let standardOutput: any Sink
  /// The borrowed standard-error stream.
  public let standardError: any Sink
  /// The startup-program provider.
  public let startupProgramProvider: any StartupProgramProvider
  /// An optional application authorization provider.
  public let jobAuthorizationProvider: (any JobAuthorizationProvider)?
  /// An optional application executive-input provider.
  public let interactiveExecutiveProvider: (any InteractiveExecutiveProvider)?
  /// Whether the language-visible interactive executive is installed.
  public let interactiveExecutiveEnabled: Bool
  /// The lifecycle observer.
  public let lifecycleObserver: any InterpreterLifecycleObserver

  /// Creates a host configuration.
  ///
  /// Streams are borrowed. The PostScript interpreter never closes them.
  public init(
    standardInput: any Source = FileSource(fileHandle: .standardInput),
    standardOutput: any Sink = FileSink(fileHandle: .standardOutput),
    standardError: any Sink = FileSink(fileHandle: .standardError),
    startupProgramProvider: any StartupProgramProvider = NoStartupProgramProvider(),
    jobAuthorizationProvider: (any JobAuthorizationProvider)? = nil,
    interactiveExecutiveProvider: (any InteractiveExecutiveProvider)? = nil,
    interactiveExecutiveEnabled: Bool = true,
    lifecycleObserver: any InterpreterLifecycleObserver = NoInterpreterLifecycleObserver()
  ) {
    self.standardInput = standardInput
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.startupProgramProvider = startupProgramProvider
    self.jobAuthorizationProvider = jobAuthorizationProvider
    self.interactiveExecutiveProvider = interactiveExecutiveProvider
    self.interactiveExecutiveEnabled = interactiveExecutiveEnabled
    self.lifecycleObserver = lifecycleObserver
  }
}
