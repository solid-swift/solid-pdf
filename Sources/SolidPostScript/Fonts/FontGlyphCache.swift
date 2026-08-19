import Foundation
import Synchronization

struct FontGlyphProgramCacheKey: Sendable, Hashable {
  let font: GraphicsFontIdentifier
  let selector: GraphicsGlyphSelector
  let writingMode: Int
  let revision: UInt64
}

struct FontGlyphRealizationCacheKey: Sendable, Hashable {
  let program: FontGlyphProgramCacheKey
  let transform: FontGlyphTransformKey
  let device: GraphicsDeviceDescriptor
  let paint: GraphicsPaint
}

struct FontGlyphTransformKey: Sendable, Hashable {
  let a: Double
  let b: Double
  let c: Double
  let d: Double
  let phaseX: Double
  let phaseY: Double

  init(_ matrix: GraphicsMatrix) {
    a = matrix.a
    b = matrix.b
    c = matrix.c
    d = matrix.d
    phaseX = Self.phase(matrix.tx)
    phaseY = Self.phase(matrix.ty)
  }

  private static func phase(_ value: Double) -> Double {
    let result = value - value.rounded(.down)
    return result == 1 ? 0 : result
  }
}

private struct PinnedFontGlyphCacheKey: Sendable, Hashable {
  let font: GraphicsFontIdentifier
  let selector: GraphicsGlyphSelector
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
    var programs: [FontGlyphProgramCacheKey: Entry] = [:]
    var realizations: [FontGlyphRealizationCacheKey: Entry] = [:]
    var pinnedEntries: [PinnedFontGlyphCacheKey: Entry] = [:]
    var bytes = 0
    var maximumBytes = FontGlyphCache.maximumBytes
    var recency: UInt64 = 0

    var entryCount: Int { programs.count + realizations.count }
  }

  private let state = Mutex(State())

  func program(for key: FontGlyphProgramCacheKey) -> GraphicsGlyphDescription? {
    state.withLock { state in
      guard var entry = state.programs[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.programs[key] = entry
      return entry.glyph
    }
  }

  func realization(for key: FontGlyphRealizationCacheKey) -> GraphicsGlyphDescription? {
    state.withLock { state in
      guard var entry = state.realizations[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.realizations[key] = entry
      return entry.glyph
    }
  }

  func insertProgram(
    _ glyph: GraphicsGlyphDescription,
    for key: FontGlyphProgramCacheKey,
    maximumItemBytes: Int
  ) {
    insert(
      glyph,
      maximumItemBytes: maximumItemBytes,
      contains: { $0.programs[key] != nil }
    ) { state, entry in
      state.programs[key] = entry
    }
  }

  func insertRealization(
    _ glyph: GraphicsGlyphDescription,
    for key: FontGlyphRealizationCacheKey,
    maximumItemBytes: Int
  ) {
    insert(
      glyph,
      maximumItemBytes: maximumItemBytes,
      contains: { $0.realizations[key] != nil }
    ) { state, entry in
      state.realizations[key] = entry
    }
  }

  private func insert(
    _ glyph: GraphicsGlyphDescription,
    maximumItemBytes: Int,
    contains: (State) -> Bool,
    store: (inout State, Entry) -> Void
  ) {
    let bytes = footprint(glyph)
    let itemLimit = min(max(0, maximumItemBytes), Self.maximumItemBytes)
    guard bytes <= itemLimit else { return }
    state.withLock { state in
      guard !contains(state) else { return }
      guard bytes <= state.maximumBytes else { return }
      while state.entryCount > 0,
        state.entryCount >= Self.maximumEntries || state.bytes > state.maximumBytes - bytes
      {
        evictOldest(state: &state)
      }
      guard state.entryCount < Self.maximumEntries, state.bytes <= state.maximumBytes - bytes else { return }
      state.recency &+= 1
      store(&state, Entry(glyph: glyph, bytes: bytes, recency: state.recency))
      state.bytes += bytes
    }
  }

  func pinnedGlyph(
    font: GraphicsFontIdentifier,
    selector: GraphicsGlyphSelector
  ) -> GraphicsGlyphDescription? {
    state.withLock { state in
      let key = PinnedFontGlyphCacheKey(font: font, selector: selector)
      guard var entry = state.pinnedEntries[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.pinnedEntries[key] = entry
      return entry.glyph
    }
  }

  func insertPinned(
    _ glyph: GraphicsGlyphDescription,
    font: GraphicsFontIdentifier,
    selector: GraphicsGlyphSelector,
    maximumItemBytes: Int
  ) -> Bool {
    let bytes = footprint(glyph)
    let itemLimit = min(max(0, maximumItemBytes), Self.maximumItemBytes)
    guard bytes <= itemLimit else { return false }
    return state.withLock { state in
      let key = PinnedFontGlyphCacheKey(font: font, selector: selector)
      let replacedBytes = state.pinnedEntries[key]?.bytes ?? 0
      while state.entryCount > 0, state.bytes - replacedBytes > state.maximumBytes - bytes {
        evictOldest(state: &state)
      }
      guard state.bytes - replacedBytes <= state.maximumBytes - bytes else { return false }
      state.recency &+= 1
      state.pinnedEntries[key] = Entry(glyph: glyph, bytes: bytes, recency: state.recency)
      state.bytes += bytes - replacedBytes
      return true
    }
  }

  func removePinned(
    font: GraphicsFontIdentifier,
    cidRange: ClosedRange<UInt32>?
  ) {
    state.withLock { state in
      let keys = state.pinnedEntries.keys.filter { key in
        guard key.font == font else { return false }
        guard let cidRange else { return true }
        guard case .cid(let cid) = key.selector else { return false }
        return cidRange.contains(cid)
      }
      for key in keys {
        if let removed = state.pinnedEntries.removeValue(forKey: key) { state.bytes -= removed.bytes }
      }
    }
  }

  func setMaximumBytes(_ requested: Int) {
    state.withLock { state in
      state.maximumBytes = min(max(0, requested), Self.maximumBytes)
      while state.bytes > state.maximumBytes, state.entryCount > 0 { evictOldest(state: &state) }
    }
  }

  func status() -> Status {
    state.withLock {
      Status(
        bytes: $0.bytes,
        maximumBytes: $0.maximumBytes,
        entries: $0.entryCount + $0.pinnedEntries.count
      )
    }
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
    let oldestProgram = state.programs.min(by: { $0.value.recency < $1.value.recency })
    let oldestRealization = state.realizations.min(by: { $0.value.recency < $1.value.recency })
    if let oldestProgram,
      oldestRealization == nil || oldestProgram.value.recency <= oldestRealization!.value.recency
    {
      state.bytes -= oldestProgram.value.bytes
      state.programs.removeValue(forKey: oldestProgram.key)
    } else if let oldestRealization {
      state.bytes -= oldestRealization.value.bytes
      state.realizations.removeValue(forKey: oldestRealization.key)
    }
  }
}
