import Foundation
import Synchronization

struct PatternCacheKey: Sendable, Hashable {
  let identity: ObjectIdentifier?
  let revision: UInt64
  let xuid: [Int32]?
  let matrix: GraphicsMatrix
  let device: GraphicsDeviceDescriptor
  let savedState: GraphicsStateSnapshot
}

final class PatternCache: Sendable {
  static let maximumBytes = 64 * 1_024 * 1_024
  static let maximumItemBytes = 8 * 1_024 * 1_024
  static let maximumEntries = 65_536

  struct Status: Sendable {
    let bytes: Int
    let maximumBytes: Int
  }

  private struct Entry {
    let pattern: GraphicsTilingPattern
    let bytes: Int
    var recency: UInt64
  }

  private struct State {
    var entries: [PatternCacheKey: Entry] = [:]
    var shadings: [PatternCacheKey: ShadingEntry] = [:]
    var bytes = 0
    var maximumBytes = PatternCache.maximumBytes
    var recency: UInt64 = 0
  }

  private struct ShadingEntry {
    let shading: GraphicsShading
    let bytes: Int
    var recency: UInt64
  }

  private let state = Mutex(State())

  func pattern(for key: PatternCacheKey) -> GraphicsTilingPattern? {
    state.withLock { state -> GraphicsTilingPattern? in
      guard var entry = state.entries[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.entries[key] = entry
      return entry.pattern
    }
  }

  func insert(
    _ pattern: GraphicsTilingPattern,
    for key: PatternCacheKey,
    maximumItemBytes: Int
  ) {
    let bytes = Self.footprint(pattern)
    let itemLimit = min(max(0, maximumItemBytes), Self.maximumItemBytes)
    guard bytes <= itemLimit else { return }
    state.withLock { state in
      guard bytes <= state.maximumBytes, state.entries[key] == nil else { return }
      evict(bytes: bytes, state: &state)
      guard state.entries.count + state.shadings.count < Self.maximumEntries,
        state.bytes <= state.maximumBytes - bytes
      else { return }
      state.recency &+= 1
      state.entries[key] = Entry(pattern: pattern, bytes: bytes, recency: state.recency)
      state.bytes += bytes
    }
  }

  func shading(for key: PatternCacheKey) -> GraphicsShading? {
    state.withLock { state -> GraphicsShading? in
      guard var entry = state.shadings[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.shadings[key] = entry
      return entry.shading
    }
  }

  func insert(_ shading: GraphicsShading, for key: PatternCacheKey, maximumItemBytes: Int) {
    let multiplication = shading.mesh.triangles.count.multipliedReportingOverflow(
      by: MemoryLayout<GraphicsShadingTriangle>.stride
    )
    guard !multiplication.overflow else { return }
    let addition = multiplication.partialValue.addingReportingOverflow(512)
    guard !addition.overflow else { return }
    let bytes = addition.partialValue
    let itemLimit = min(max(0, maximumItemBytes), Self.maximumItemBytes)
    guard bytes <= itemLimit else { return }
    state.withLock { state in
      guard bytes <= state.maximumBytes, state.shadings[key] == nil else { return }
      evict(bytes: bytes, state: &state)
      guard state.entries.count + state.shadings.count < Self.maximumEntries,
        state.bytes <= state.maximumBytes - bytes
      else { return }
      state.recency &+= 1
      state.shadings[key] = ShadingEntry(shading: shading, bytes: bytes, recency: state.recency)
      state.bytes += bytes
    }
  }

  func setMaximumBytes(_ requested: Int) {
    state.withLock { state in
      state.maximumBytes = min(max(0, requested), Self.maximumBytes)
      while state.bytes > state.maximumBytes,
        !state.entries.isEmpty || !state.shadings.isEmpty
      {
        evictOldest(state: &state)
      }
    }
  }

  func status() -> Status {
    state.withLock { Status(bytes: $0.bytes, maximumBytes: $0.maximumBytes) }
  }

  private static func footprint(_ pattern: GraphicsTilingPattern) -> Int {
    var bytes = 256
    for effect in pattern.displayList.effects {
      let addition = bytes.addingReportingOverflow(footprint(effect))
      guard !addition.overflow else { return .max }
      bytes = addition.partialValue
    }
    return bytes
  }

  private func evict(bytes: Int, state: inout State) {
    while !state.entries.isEmpty || !state.shadings.isEmpty {
      guard state.entries.count + state.shadings.count >= Self.maximumEntries
        || state.bytes > state.maximumBytes - bytes
      else { return }
      evictOldest(state: &state)
    }
  }

  private func evictOldest(state: inout State) {
    let pattern = state.entries.min(by: { $0.value.recency < $1.value.recency })
    let shading = state.shadings.min(by: { $0.value.recency < $1.value.recency })
    switch (pattern, shading) {
    case (.some(let pattern), .some(let shading)) where pattern.value.recency <= shading.value.recency:
      state.bytes -= pattern.value.bytes
      state.entries.removeValue(forKey: pattern.key)
    case (.some, .some(let shading)), (nil, .some(let shading)):
      state.bytes -= shading.value.bytes
      state.shadings.removeValue(forKey: shading.key)
    case (.some(let pattern), nil):
      state.bytes -= pattern.value.bytes
      state.entries.removeValue(forKey: pattern.key)
    case (nil, nil):
      break
    }
  }

  private static func footprint(_ effect: GraphicsEffect) -> Int {
    switch effect {
    case .fill(let path, _, _), .stroke(let path, _), .userPathFill(let path, _, _),
         .userPathStroke(let path, _):
      path.elements.count * 56 + 256
    case .fillRectangles(let paths, _), .strokeRectangles(let paths, _, _):
      paths.reduce(256) { partial, path in
        let elementBytes = path.elements.count.multipliedReportingOverflow(by: 56)
        guard !elementBytes.overflow else { return .max }
        let total = partial.addingReportingOverflow(elementBytes.partialValue)
        return total.overflow ? .max : total.partialValue
      }
    case .image(let image, _):
      image.components.count * MemoryLayout<Float>.stride
        + (image.sourceComponents?.count ?? 0) * MemoryLayout<Float>.stride + 256
    case .shading(let shading, _):
      shading.mesh.triangles.count * MemoryLayout<GraphicsShadingTriangle>.stride + 256
    case .erase:
      128
    }
  }
}
