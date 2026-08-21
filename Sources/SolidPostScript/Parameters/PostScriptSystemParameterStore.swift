import Foundation
import Synchronization

/// An opaque generation of persistent PostScript installation parameters.
public struct PostScriptSystemParameterRecord: Sendable, Equatable {
  /// The monotonically increasing compare-and-replace generation.
  public let generation: UInt64
  /// Versioned bytes owned by SolidPostScript and persisted without interpretation by the host.
  public let opaquePayload: Data

  /// Creates an opaque record, typically while reconstructing a durable host store.
  public init(generation: UInt64, opaquePayload: Data) {
    self.generation = generation
    self.opaquePayload = opaquePayload
  }
}

/// Persistent storage for mutable installation-level PostScript parameters.
public protocol PostScriptSystemParameterStore: Sendable {
  /// Loads the latest record, or returns `nil` for a new installation.
  func load() throws -> PostScriptSystemParameterRecord?

  /// Replaces the record only when its current generation equals `expectedGeneration`.
  func compareAndReplace(
    expectedGeneration: UInt64?,
    with record: PostScriptSystemParameterRecord
  ) throws -> Bool
}

/// An isolated in-process implementation suitable for tests and nondurable installations.
public final class ProcessLocalSystemParameterStore: PostScriptSystemParameterStore, Sendable {
  private let record = Mutex<PostScriptSystemParameterRecord?>(nil)

  /// Creates an empty process-local installation store.
  public init() {}

  /// Loads the process-local record atomically.
  public func load() -> PostScriptSystemParameterRecord? {
    record.withLock { $0 }
  }

  /// Replaces the process-local record when `expectedGeneration` still matches.
  public func compareAndReplace(
    expectedGeneration: UInt64?,
    with replacement: PostScriptSystemParameterRecord
  ) -> Bool {
    record.withLock { record in
      guard record?.generation == expectedGeneration else { return false }
      let expectedNext: UInt64
      if let expectedGeneration {
        let incremented = expectedGeneration.addingReportingOverflow(1)
        guard !incremented.overflow else { return false }
        expectedNext = incremented.partialValue
      } else {
        expectedNext = 1
      }
      guard replacement.generation == expectedNext else { return false }
      record = replacement
      return true
    }
  }
}
