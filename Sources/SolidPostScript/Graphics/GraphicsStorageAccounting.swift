import Synchronization

/// A category of retained graphics storage governed by Appendix C system parameters.
public enum GraphicsRetainedStorageKind: Sendable, Hashable {
  /// Marks retained until they are scan-converted or emitted by a target.
  case displayList
  /// Sample data retained for images or uncached glyphs.
  case sourceList
  /// One materialized sampled-image buffer, also counted as source-list storage.
  case imageBuffer
}

/// An error produced when graphics storage cannot be reserved within the active limits.
public enum GraphicsStorageAccountingError: Swift.Error, Sendable, Equatable {
  /// The requested storage would exceed an Appendix C limit.
  case limitExceeded
}

/// A shared reservation against one render environment's graphics-storage limits.
///
/// A reservation may be retained by multiple immutable output references. Storage is
/// released exactly once, either explicitly or when the reservation is destroyed.
public final class GraphicsStorageReservation: Sendable {
  private struct State: Sendable {
    var bytes: Int
    var released = false
  }

  private let session: GraphicsStorageAccountingSession
  private let kind: GraphicsRetainedStorageKind
  private let state: Mutex<State>

  fileprivate init(
    session: GraphicsStorageAccountingSession,
    kind: GraphicsRetainedStorageKind,
    bytes: Int
  ) {
    self.session = session
    self.kind = kind
    self.state = Mutex(State(bytes: bytes))
  }

  deinit {
    release()
  }

  /// The number of bytes currently charged by this reservation.
  public var bytes: Int {
    state.withLock { $0.released ? 0 : $0.bytes }
  }

  /// Changes the reservation to `bytes`, checking every applicable limit before growth.
  public func resize(to bytes: Int) throws {
    guard bytes >= 0 else { throw GraphicsStorageAccountingError.limitExceeded }
    try state.withLock { state in
      guard !state.released else {
        if bytes == 0 { return }
        throw GraphicsStorageAccountingError.limitExceeded
      }
      try session.resize(kind: kind, from: state.bytes, to: bytes)
      state.bytes = bytes
    }
  }

  /// Releases this reservation. Repeated releases have no effect.
  public func release() {
    state.withLock { state in
      guard !state.released else { return }
      session.release(kind: kind, bytes: state.bytes)
      state.bytes = 0
      state.released = true
    }
  }
}

/// A render-scoped interface to one environment's Appendix C storage accounting.
///
/// Targets that retain display lists or sampled source data should reserve storage
/// before allocating it. Existing targets may ignore this session through the
/// default ``GraphicsRenderer/installStorageAccounting(_:)`` implementation.
public final class GraphicsStorageAccountingSession: Sendable {
  private let ledger: GraphicsStorageLedger

  init(ledger: GraphicsStorageLedger) {
    self.ledger = ledger
  }

  /// Reserves `bytes` in `kind` and returns its independently releasable ownership token.
  public func reserve(
    _ kind: GraphicsRetainedStorageKind,
    bytes: Int
  ) throws -> GraphicsStorageReservation {
    guard bytes >= 0 else { throw GraphicsStorageAccountingError.limitExceeded }
    try ledger.resize(kind: kind, from: 0, to: bytes)
    return GraphicsStorageReservation(session: self, kind: kind, bytes: bytes)
  }

  fileprivate func resize(kind: GraphicsRetainedStorageKind, from old: Int, to new: Int) throws {
    try ledger.resize(kind: kind, from: old, to: new)
  }

  fileprivate func release(kind: GraphicsRetainedStorageKind, bytes: Int) {
    ledger.release(kind: kind, bytes: bytes)
  }
}

final class GraphicsStorageLedger: Sendable {
  static let maximumDisplayBytes = 512 * 1_024 * 1_024
  static let maximumSourceBytes = 512 * 1_024 * 1_024
  static let maximumCombinedBytes = 512 * 1_024 * 1_024
  static let maximumImageBufferBytes = 512 * 1_024 * 1_024

  struct Status: Sendable {
    let displayBytes: Int
    let sourceBytes: Int
    let maximumDisplayBytes: Int
    let maximumSourceBytes: Int
    let maximumCombinedBytes: Int
    let maximumImageBufferBytes: Int
  }

  private struct State: Sendable {
    var displayBytes = 0
    var sourceBytes = 0
    var maximumDisplayBytes = GraphicsStorageLedger.maximumDisplayBytes
    var maximumSourceBytes = GraphicsStorageLedger.maximumSourceBytes
    var maximumCombinedBytes = GraphicsStorageLedger.maximumCombinedBytes
    var maximumImageBufferBytes = GraphicsStorageLedger.maximumImageBufferBytes
  }

  private let state = Mutex(State())

  func makeSession() -> GraphicsStorageAccountingSession {
    GraphicsStorageAccountingSession(ledger: self)
  }

  func status() -> Status {
    state.withLock {
      Status(
        displayBytes: $0.displayBytes,
        sourceBytes: $0.sourceBytes,
        maximumDisplayBytes: $0.maximumDisplayBytes,
        maximumSourceBytes: $0.maximumSourceBytes,
        maximumCombinedBytes: $0.maximumCombinedBytes,
        maximumImageBufferBytes: $0.maximumImageBufferBytes
      )
    }
  }

  func setLimits(display: Int, source: Int, combined: Int, imageBuffer: Int) {
    state.withLock { state in
      state.maximumDisplayBytes = min(max(0, display), Self.maximumDisplayBytes)
      state.maximumSourceBytes = min(max(0, source), Self.maximumSourceBytes)
      state.maximumCombinedBytes = min(
        max(combined, state.maximumDisplayBytes, state.maximumSourceBytes),
        Self.maximumCombinedBytes
      )
      state.maximumImageBufferBytes = min(max(0, imageBuffer), Self.maximumImageBufferBytes)
    }
  }

  func resize(kind: GraphicsRetainedStorageKind, from old: Int, to new: Int) throws {
    guard old >= 0, new >= 0 else { throw GraphicsStorageAccountingError.limitExceeded }
    try state.withLock { state in
      let delta = new.subtractingReportingOverflow(old)
      guard !delta.overflow else { throw GraphicsStorageAccountingError.limitExceeded }
      guard delta.partialValue > 0 else {
        release(kind: kind, bytes: -delta.partialValue, state: &state)
        return
      }

      switch kind {
      case .displayList:
        let display = state.displayBytes.addingReportingOverflow(delta.partialValue)
        let combined = state.displayBytes.addingReportingOverflow(state.sourceBytes)
        guard !display.overflow, !combined.overflow,
          display.partialValue <= state.maximumDisplayBytes,
          combined.partialValue <= state.maximumCombinedBytes - delta.partialValue
        else { throw GraphicsStorageAccountingError.limitExceeded }
        state.displayBytes = display.partialValue

      case .sourceList, .imageBuffer:
        guard kind != .imageBuffer || new <= state.maximumImageBufferBytes else {
          throw GraphicsStorageAccountingError.limitExceeded
        }
        let source = state.sourceBytes.addingReportingOverflow(delta.partialValue)
        let combined = state.displayBytes.addingReportingOverflow(state.sourceBytes)
        guard !source.overflow, !combined.overflow,
          source.partialValue <= state.maximumSourceBytes,
          combined.partialValue <= state.maximumCombinedBytes - delta.partialValue
        else { throw GraphicsStorageAccountingError.limitExceeded }
        state.sourceBytes = source.partialValue
      }
    }
  }

  func release(kind: GraphicsRetainedStorageKind, bytes: Int) {
    guard bytes > 0 else { return }
    state.withLock { release(kind: kind, bytes: bytes, state: &$0) }
  }

  private func release(kind: GraphicsRetainedStorageKind, bytes: Int, state: inout State) {
    switch kind {
    case .displayList:
      state.displayBytes = max(0, state.displayBytes - bytes)
    case .sourceList, .imageBuffer:
      state.sourceBytes = max(0, state.sourceBytes - bytes)
    }
  }
}
