import Foundation
import Synchronization

struct FormCacheKey: Sendable, Hashable {
  let identity: ObjectIdentifier?
  let revision: UInt64
  let xuid: [Int32]?
  let bounds: GraphicsRect
  let matrix: GraphicsMatrix
  let paintProcedureIdentity: ObjectIdentifier
  let device: GraphicsDeviceDescriptor
  let savedState: GraphicsStateSnapshot
}

final class FormCache: Sendable {
  static let maximumBytes = 64 * 1_024 * 1_024
  static let maximumItemBytes = 8 * 1_024 * 1_024
  static let maximumEntries = 65_536

  struct Status: Sendable {
    let bytes: Int
    let maximumBytes: Int
  }

  private struct Entry {
    let form: GraphicsForm
    let bytes: Int
    var recency: UInt64
  }

  private struct State {
    var entries: [FormCacheKey: Entry] = [:]
    var bytes = 0
    var maximumBytes = FormCache.maximumBytes
    var recency: UInt64 = 0
  }

  private let state = Mutex(State())

  func form(for key: FormCacheKey) -> GraphicsForm? {
    state.withLock { state -> GraphicsForm? in
      guard var entry = state.entries[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.entries[key] = entry
      return entry.form
    }
  }

  func insert(_ form: GraphicsForm, for key: FormCacheKey, maximumItemBytes: Int) {
    let bytes = form.displayList.checkedFootprint()
    let itemLimit = min(max(0, maximumItemBytes), Self.maximumItemBytes)
    guard bytes <= itemLimit else { return }
    state.withLock { state in
      guard bytes <= state.maximumBytes, state.entries[key] == nil else { return }
      while !state.entries.isEmpty,
        state.entries.count >= Self.maximumEntries || state.bytes > state.maximumBytes - bytes
      {
        evictOldest(state: &state)
      }
      guard state.entries.count < Self.maximumEntries, state.bytes <= state.maximumBytes - bytes else { return }
      state.recency &+= 1
      state.entries[key] = Entry(form: form, bytes: bytes, recency: state.recency)
      state.bytes += bytes
    }
  }

  func setMaximumBytes(_ requested: Int) {
    state.withLock { state in
      state.maximumBytes = min(max(0, requested), Self.maximumBytes)
      while state.bytes > state.maximumBytes, !state.entries.isEmpty {
        evictOldest(state: &state)
      }
    }
  }

  func status() -> Status {
    state.withLock { Status(bytes: $0.bytes, maximumBytes: $0.maximumBytes) }
  }

  private func evictOldest(state: inout State) {
    guard let oldest = state.entries.min(by: { $0.value.recency < $1.value.recency }) else { return }
    state.bytes -= oldest.value.bytes
    state.entries.removeValue(forKey: oldest.key)
  }
}
