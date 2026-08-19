import Foundation
import Synchronization

struct ScreenCacheKey: Sendable, Hashable {
  let sourceIdentity: ObjectIdentifier?
  let sourceRevision: UInt64
  let descriptor: GraphicsDeviceDescriptor
  let accurate: Bool
  let maximumSuperScreen: Int32
}

final class ScreenManager: Sendable {
  static let maximumActiveBytes = 64 * 1_024 * 1_024
  static let maximumCachedBytes = 64 * 1_024 * 1_024
  static let maximumItemBytes = 16 * 1_024 * 1_024
  static let maximumEntries = 65_536

  struct Status: Sendable {
    let activeBytes: Int
    let cachedBytes: Int
    let maximumActiveBytes: Int
    let maximumCachedBytes: Int
  }

  private struct Entry: Sendable {
    let screen: GraphicsHalftone
    let bytes: Int
    var recency: UInt64
  }

  private struct State: Sendable {
    var entries: [ScreenCacheKey: Entry] = [:]
    var cachedBytes = 0
    var maximumActiveBytes = ScreenManager.maximumActiveBytes
    var maximumCachedBytes = ScreenManager.maximumCachedBytes
    var recency: UInt64 = 0
    var active: [WeakScreenLease] = []
  }

  private let state = Mutex(State())

  func lease(_ screen: GraphicsHalftone) throws -> ScreenLease? {
    let bytes = Self.footprint(screen)
    guard bytes > 0 else { return nil }
    return try state.withLock { state in
      state.active.removeAll { $0.value == nil }
      let activeBytes = state.active.reduce(0) { $0 + ($1.value?.bytes ?? 0) }
      guard bytes <= state.maximumActiveBytes, activeBytes <= state.maximumActiveBytes - bytes else {
        throw Error.limitCheck
      }
      let lease = ScreenLease(screen: screen, bytes: bytes)
      state.active.append(WeakScreenLease(lease))
      return lease
    }
  }

  func screen(for key: ScreenCacheKey) -> GraphicsHalftone? {
    state.withLock { state in
      guard var entry = state.entries[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.entries[key] = entry
      return entry.screen
    }
  }

  func insert(_ screen: GraphicsHalftone, for key: ScreenCacheKey, maximumItemBytes: Int) {
    let bytes = Self.footprint(screen)
    let itemLimit = min(max(0, maximumItemBytes), Self.maximumItemBytes)
    guard bytes <= itemLimit else { return }
    state.withLock { state in
      guard bytes <= state.maximumCachedBytes, state.entries[key] == nil else { return }
      while !state.entries.isEmpty,
        state.entries.count >= Self.maximumEntries || state.cachedBytes > state.maximumCachedBytes - bytes
      {
        evictOldest(state: &state)
      }
      guard state.entries.count < Self.maximumEntries,
        state.cachedBytes <= state.maximumCachedBytes - bytes
      else { return }
      state.recency &+= 1
      state.entries[key] = Entry(screen: screen, bytes: bytes, recency: state.recency)
      state.cachedBytes += bytes
    }
  }

  func setMaximumActiveBytes(_ requested: Int) {
    state.withLock { $0.maximumActiveBytes = min(max(0, requested), Self.maximumActiveBytes) }
  }

  func setMaximumCachedBytes(_ requested: Int) {
    state.withLock { state in
      state.maximumCachedBytes = min(max(0, requested), Self.maximumCachedBytes)
      while state.cachedBytes > state.maximumCachedBytes, !state.entries.isEmpty {
        evictOldest(state: &state)
      }
    }
  }

  func status() -> Status {
    state.withLock { state in
      state.active.removeAll { $0.value == nil }
      return Status(
        activeBytes: state.active.reduce(0) { $0 + ($1.value?.bytes ?? 0) },
        cachedBytes: state.cachedBytes,
        maximumActiveBytes: state.maximumActiveBytes,
        maximumCachedBytes: state.maximumCachedBytes
      )
    }
  }

  static func footprint(_ screen: GraphicsHalftone) -> Int {
    switch screen {
    case .continuous:
      0
    case .spot(let screen):
      64 + screen.thresholds.count * MemoryLayout<UInt16>.stride
    case .threshold(let screen):
      32 + screen.thresholds.count * MemoryLayout<UInt16>.stride
    case .colorants(let screens):
      64 + screens.reduce(0) { $0 + $1.key.utf8.count + footprint($1.value) }
    }
  }

  private func evictOldest(state: inout State) {
    guard let oldest = state.entries.min(by: { $0.value.recency < $1.value.recency }) else { return }
    state.cachedBytes -= oldest.value.bytes
    state.entries.removeValue(forKey: oldest.key)
  }
}

final class ScreenLease: Sendable {
  let screen: GraphicsHalftone
  let bytes: Int

  init(screen: GraphicsHalftone, bytes: Int) {
    self.screen = screen
    self.bytes = bytes
  }
}

private final class WeakScreenLease: @unchecked Sendable {
  weak var value: ScreenLease?

  init(_ value: ScreenLease) {
    self.value = value
  }
}
