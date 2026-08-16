//
//  HostLifecycleOps.swift
//

import Foundation
import SolidCore

extension Operators {

  static let hostLifecycleOps: [OperatorValue] = [
    StartJob.instance,
    Executive.instance,
    Echo.instance,
  ]

  static let startProcedure = neverThrow(
    try Object.array(
      [Object(value: Start.instance)],
      access: .readOnly,
      vm: .global,
      kind: .executable
    )
  )

  static let promptProcedure = neverThrow(
    try Object.array(
      [
        .string("PS>", access: .readOnly, vm: .global, kind: .literal),
        Object(value: Print.instance),
        Object(value: FlushStd.instance),
      ],
      access: .readOnly,
      vm: .global,
      kind: .executable
    )
  )

  static let quitMaskProcedure = neverThrow(
    try Object.array(
      [Object(value: Stop.instance)],
      access: .readOnly,
      vm: .global,
      kind: .executable
    )
  )

  static let serverDictionary = neverThrow(
    try Object.dictionary(
      ["exitserver": Object(value: ExitServer.instance)],
      access: .readOnly,
      vm: .global,
      kind: .literal
    )
  )

  enum Start: OperatorValue {
    case instance

    static let systemDictionaryNames: [Object] = []

    func execute(context: isolated Context) async throws {
      let content: Data?
      do {
        content = try await context.withUserTimeSuspended {
          try await context.environment.startupProgram()
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw Error.ioError
      }
      guard let content else { return }
      let file = DataFile(data: content, mode: .read)
      let source = Object.file(file, access: .readOnly, vm: .local, kind: .executable)
      try context.execution.push(source: source, in: context)
    }
  }

  /// Implements the PostScript `startjob` operator.
  public enum StartJob: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["startjob"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let (password, persistentObject) = try context.operands.pop2()
      let persistent = try persistentObject.value(as: BooleanValue.self).value
      let candidate = try ParameterValue.password(from: password)

      guard context.jobServerEnabled,
        let job = context.jobLifecycle,
        context.saveDepth == job.startSaveDepth
      else {
        context.operands.push(.boolean(false))
        return
      }

      let request = JobAuthorizationRequest(
        purpose: .startJob,
        candidate: candidate,
        persistent: persistent
      )
      let authorization = try await authorize(request, context: context)
      guard authorization != .denied else {
        context.operands.push(.boolean(false))
        return
      }

      let priorPersistent = job.persistent
      try await context.transitionJob(persistent: persistent, authorization: authorization)
      context.operands.push(.boolean(true))
      try await context.withUserTimeSuspended {
        try await context.environment.emit(.jobFinished(persistent: priorPersistent))
        try await context.environment.emit(.jobStarted(persistent: persistent))
      }
    }
  }

  enum ExitServer: OperatorValue {
    case instance

    static let systemDictionaryNames: [Object] = ["exitserver"]

    func execute(context: isolated Context) async throws {
      let password = try context.operands.pop()
      let request = JobAuthorizationRequest(
        purpose: .exitServer,
        candidate: try ParameterValue.password(from: password),
        persistent: true
      )
      guard context.jobServerEnabled,
        let job = context.jobLifecycle,
        context.saveDepth == job.startSaveDepth
      else {
        throw Error.invalidAccess
      }

      let authorization = try await authorize(request, context: context)
      guard authorization != .denied else {
        throw Error.invalidAccess
      }

      let priorPersistent = job.persistent
      let suppressNotice = try context.binaryErrorReportingEnabled()
      try await context.transitionJob(persistent: true, authorization: authorization)
      try await context.withUserTimeSuspended {
        try await context.environment.emit(.jobFinished(persistent: priorPersistent))
        try await context.environment.emit(.jobStarted(persistent: true))
        if !suppressNotice {
          try await context.environment.emit(.exitServerAuthorized)
        }
      }
    }
  }

  /// Implements the PostScript `echo` operator.
  public enum Echo: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["echo"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let enabled: BooleanValue = try context.operands.popAs()
      context.echoEnabled = enabled.value
    }
  }

  /// Implements the PostScript `executive` operator.
  public enum Executive: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["executive"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try await context.runExecutive()
    }
  }

  private static func authorize(
    _ request: JobAuthorizationRequest,
    context: isolated Context
  ) async throws -> JobAuthorizationOutcome {
    do {
      return try await context.withUserTimeSuspended {
        try await context.environment.authorize(request)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Error.ioError
    }
  }
}
