import Foundation
import Synchronization

struct FontGlyphCacheKey: Sendable, Hashable {
  let font: GraphicsFontIdentifier
  let selector: GraphicsGlyphSelector
  let transform: GraphicsMatrix
  let writingMode: Int
  let revision: UInt64
}

final class FontGlyphCache: Sendable {
  static let maximumBytes = 64 * 1_024 * 1_024
  static let maximumItemBytes = 4 * 1_024 * 1_024
  static let maximumEntries = 65_536

  struct Status: Sendable {
    let bytes: Int
    let maximumBytes: Int
    let entries: Int
  }

  private struct Entry {
    let glyph: GraphicsGlyphDescription
    let bytes: Int
    var recency: UInt64
  }

  private struct State {
    var entries: [FontGlyphCacheKey: Entry] = [:]
    var bytes = 0
    var maximumBytes = FontGlyphCache.maximumBytes
    var recency: UInt64 = 0
  }

  private let state = Mutex(State())

  func glyph(for key: FontGlyphCacheKey) -> GraphicsGlyphDescription? {
    state.withLock { state in
      guard var entry = state.entries[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.entries[key] = entry
      return entry.glyph
    }
  }

  func insert(_ glyph: GraphicsGlyphDescription, for key: FontGlyphCacheKey, maximumItemBytes: Int) {
    let bytes = footprint(glyph)
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
      state.entries[key] = Entry(glyph: glyph, bytes: bytes, recency: state.recency)
      state.bytes += bytes
    }
  }

  func setMaximumBytes(_ requested: Int) {
    state.withLock { state in
      state.maximumBytes = min(max(0, requested), Self.maximumBytes)
      while state.bytes > state.maximumBytes, !state.entries.isEmpty { evictOldest(state: &state) }
    }
  }

  func status() -> Status {
    state.withLock { Status(bytes: $0.bytes, maximumBytes: $0.maximumBytes, entries: $0.entries.count) }
  }

  private func footprint(_ glyph: GraphicsGlyphDescription) -> Int {
    switch glyph.program {
    case .outline(let path):
      let size = path.elements.count.multipliedReportingOverflow(by: 56)
      return size.overflow ? .max : size.partialValue + 256
    case .bitmap(let bitmap):
      let size = bitmap.coverage.count.addingReportingOverflow(256)
      return size.overflow ? .max : size.partialValue
    case .displayList(let list):
      return list.checkedFootprint()
    case .empty, .missing:
      return 128
    }
  }

  private func evictOldest(state: inout State) {
    guard let oldest = state.entries.min(by: { $0.value.recency < $1.value.recency }) else { return }
    state.bytes -= oldest.value.bytes
    state.entries.removeValue(forKey: oldest.key)
  }
}
