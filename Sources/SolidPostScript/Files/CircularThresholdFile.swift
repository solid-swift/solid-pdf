import Foundation
import Synchronization

/// An interpreter-owned circular view of materialized halftone threshold data.
final class CircularThresholdFile: File, Sendable {
  let name = "halftone thresholds"
  let mode = File.Mode.read
  let closesAtEndOfFile = false

  private struct State {
    var offset = 0
    var closed = false
  }

  private let data: Data
  private let state = Mutex(State())

  init(data: Data) {
    precondition(!data.isEmpty)
    self.data = data
  }

  var isClosed: Bool { state.withLock(\.closed) }

  func readByte() throws -> UInt8? {
    try access { state in
      let byte = data[state.offset]
      state.offset = (state.offset + 1) % data.count
      return byte
    }
  }

  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    try access { state in
      let byte = data[state.offset]
      guard predicate(byte) else { return (nil, false) }
      state.offset = (state.offset + 1) % data.count
      return (byte, false)
    }
  }

  func read(max: Int) throws -> Data? {
    guard max >= 0 else { throw Error.rangeCheck }
    return try access { state in
      var result = Data(capacity: max)
      while result.count < max {
        let count = min(max - result.count, data.count - state.offset)
        result.append(data[state.offset..<(state.offset + count)])
        state.offset = (state.offset + count) % data.count
      }
      return result
    }
  }

  func write(contentsOf data: Data) throws { throw Error.invalidAccess }

  func close() {
    state.withLock { $0.closed = true }
  }

  var offset: Int {
    get throws { try access(\.offset) }
  }

  func setOffset(_ offset: Int) throws {
    guard offset >= 0 else { throw Error.rangeCheck }
    try access { $0.offset = offset % data.count }
  }

  var available: Int {
    get throws { try access { _ in Int.max } }
  }

  var size: Int { get throws { data.count } }

  func flush() throws {
    _ = try access { _ in () }
  }

  func reset() throws {
    try access { $0.offset = 0 }
  }

  private func access<Result>(_ body: (inout State) throws -> Result) throws -> Result {
    try state.withLock { state in
      guard !state.closed else { throw Error.ioError }
      return try body(&state)
    }
  }
}
