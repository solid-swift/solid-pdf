//
//  InterpreterSession.swift
//

import Foundation

/// A durable PostScript interpreter session with PLRM job-server lifecycle behavior.
public actor InterpreterSession {

  /// The shared interpreter environment.
  public nonisolated let environment: InterpreterEnvironment

  private let context: Context
  private var started = false
  private var startupTask: Task<Void, Swift.Error>?

  /// Creates a job-server session.
  public init(environment: InterpreterEnvironment = InterpreterEnvironment()) {
    self.environment = environment
    self.context = Context(environment: environment, jobServerEnabled: true)
  }

  /// Initializes the session and executes `start` exactly once.
  public func start() async throws {
    guard !started else { return }
    if let startupTask {
      return try await startupTask.value
    }

    let context = self.context
    let environment = self.environment
    let task = Task {
      do {
        try await context.executeStart()
      } catch let stop as ErrorStop {
        throw stop.error
      } catch let undispatched as UndispatchedError {
        throw undispatched.error
      }
      try await environment.emit(.started)
    }
    startupTask = task
    do {
      try await task.value
      started = true
    } catch {
      throw error
    }
  }

  /// Executes a PostScript job supplied as text.
  @discardableResult
  public func executeJob(content: String) async throws -> Context {
    let data = content.data(using: .isoLatin1) ?? Data()
    return try await executeJob(file: DataFile(data: data, mode: .read))
  }

  /// Executes a PostScript job supplied as a file.
  @discardableResult
  public func executeJob(file: any File) async throws -> Context {
    try await start()

    let source = Object.file(file, access: .readOnly, vm: .local, kind: .executable)
    do {
      try await context.beginSessionJob()
      try await environment.emit(.jobStarted(persistent: false))
      try await context.pushAndRun(source: source)
      try await context.finishCurrentPageDevice()
      let persistent = await context.currentJobPersistent
      try await context.finishSessionJob()
      try await environment.emit(.jobFinished(persistent: persistent))
      return context
    } catch Error.control(.stop) {
      try await context.finishCurrentPageDevice()
      let persistent = await context.currentJobPersistent
      try await context.finishSessionJob()
      try await environment.emit(.jobFinished(persistent: persistent))
      return context
    } catch let stop as ErrorStop {
      try? await environment.emit(.error(stop.error.postScriptName ?? "unregistered"))
      try? await context.reportCurrentError()
      try? await context.flush(file: file)
      try? await context.finishSessionJob()
      throw stop.error
    } catch let undispatched as UndispatchedError {
      try? await environment.emit(.error(undispatched.error.postScriptName ?? "unregistered"))
      try? await context.flush(file: file)
      try? await context.finishSessionJob()
      throw undispatched.error
    } catch {
      try? await context.finishSessionJob()
      throw error
    }
  }
}
