import Foundation
import Synchronization

enum UserPathReducedOperation: Sendable, Hashable {
  case fill(GraphicsFillRule)
  case stroke(GraphicsMatrix?)
}

struct UserPathCacheKey: Sendable, Hashable {
  let definition: DecodedUserPath
  let operation: UserPathReducedOperation
  let matrix: GraphicsMatrix
  let flatness: Double
  let lineWidth: Double
  let lineCap: GraphicsLineCap
  let lineJoin: GraphicsLineJoin
  let miterLimit: Double
  let dash: GraphicsDash
  let strokeAdjustment: Bool
  let device: GraphicsDeviceDescriptor
}

final class UserPathCache: Sendable {
  static let maximumBytes = 64 * 1_024 * 1_024
  static let maximumItemBytes = 4 * 1_024 * 1_024
  static let maximumEntries = 65_536

  struct Status: Sendable {
    let bytes: Int
    let maximumBytes: Int
    let entries: Int
    let maximumEntries: Int
  }

  private struct Entry {
    let path: GraphicsPath
    let bytes: Int
    var recency: UInt64
  }

  private struct State {
    var entries: [UserPathCacheKey: Entry] = [:]
    var bytes = 0
    var maximumBytes = UserPathCache.maximumBytes
    var recency: UInt64 = 0
  }

  private let state = Mutex(State())

  func path(
    for key: UserPathCacheKey,
    maximumItemBytes: Int,
    build: () throws -> GraphicsPath
  ) rethrows -> GraphicsPath {
    if let path = state.withLock({ state -> GraphicsPath? in
      guard var entry = state.entries[key] else { return nil }
      state.recency &+= 1
      entry.recency = state.recency
      state.entries[key] = entry
      return entry.path
    }) {
      return path
    }

    let path = try build()
    let bytes = Self.footprint(path)
    let itemLimit = min(max(0, maximumItemBytes), Self.maximumItemBytes)
    guard bytes <= itemLimit else { return path }
    state.withLock { state in
      guard bytes <= state.maximumBytes else { return }
      if state.entries[key] != nil { return }
      while !state.entries.isEmpty,
        state.entries.count >= Self.maximumEntries || state.bytes > state.maximumBytes - bytes
      {
        guard let oldest = state.entries.min(by: { $0.value.recency < $1.value.recency }) else { break }
        state.bytes -= oldest.value.bytes
        state.entries.removeValue(forKey: oldest.key)
      }
      guard state.entries.count < Self.maximumEntries, state.bytes <= state.maximumBytes - bytes else { return }
      state.recency &+= 1
      state.entries[key] = Entry(path: path, bytes: bytes, recency: state.recency)
      state.bytes += bytes
    }
    return path
  }

  func setMaximumBytes(_ requested: Int) {
    state.withLock { state in
      state.maximumBytes = min(max(0, requested), Self.maximumBytes)
      while state.bytes > state.maximumBytes,
        let oldest = state.entries.min(by: { $0.value.recency < $1.value.recency })
      {
        state.bytes -= oldest.value.bytes
        state.entries.removeValue(forKey: oldest.key)
      }
    }
  }

  func status() -> Status {
    state.withLock {
      Status(
        bytes: $0.bytes,
        maximumBytes: $0.maximumBytes,
        entries: $0.entries.count,
        maximumEntries: Self.maximumEntries
      )
    }
  }

  private static func footprint(_ path: GraphicsPath) -> Int {
    let (bytes, overflow) = path.elements.count.multipliedReportingOverflow(by: 56)
    guard !overflow, bytes <= Int.max - 64 else { return .max }
    return bytes + 64
  }
}
