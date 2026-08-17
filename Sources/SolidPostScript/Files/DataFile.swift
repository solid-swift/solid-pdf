//
//  DataFile.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation
import Synchronization

/// An in-memory synchronous, seekable PostScript file.
public final class DataFile: File, Sendable {

  private struct State {
    var data: Data
    var currentIndex: Data.Index
    var closed = false

    init(data: Data, currentIndex: Data.Index) {
      self.data = data
      self.currentIndex = currentIndex
    }

    init(_ source: State) {
      self.init(data: source.data, currentIndex: source.currentIndex)
    }
  }

  /// The ``name`` value.
  public let name = "data"
  /// The ``mode`` value.
  public let mode: Mode

  private let state: Mutex<State>

  /// Creates an instance.
  public init(data: Data, mode: File.Mode) {
    self.state = Mutex(State(data: data, currentIndex: data.startIndex))
    self.mode = mode
  }

  private func access<U>(_ block: (inout State) throws -> U) throws -> U {
    return try state.withLock { state in
      guard !state.closed else {
        throw Error.ioError
      }
      return try block(&state)
    }
  }

  /// The ``isClosed`` value.
  public var isClosed: Bool {
    state.withLock { $0.closed }
  }

  /// Performs the ``readByte`` operation.
  public func readByte() throws -> UInt8? {
    try access { state in

      guard state.currentIndex < state.data.endIndex else {
        return nil
      }

      let char = state.data[state.currentIndex]
      state.currentIndex = state.data.index(after: state.currentIndex)
      return char
    }
  }

  /// Performs the ``readByte`` operation.
  public func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    try access { state in

      guard state.currentIndex < state.data.endIndex else {
        return (nil, true)
      }

      let byte = state.data[state.currentIndex]
      guard predicate(byte) else {
        return (nil, false)
      }

      state.currentIndex = state.data.index(after: state.currentIndex)
      return (byte, false)
    }
  }

  /// Performs the ``read`` operation.
  public func read(max: Int) throws -> Data? {
    try access { state in

      guard max >= 0 else {
        throw Error.rangeCheck
      }

      let currentIndex =
        state.data.index(state.currentIndex, offsetBy: max, limitedBy: state.data.endIndex)
        ?? state.data.endIndex
      let data = state.data[state.currentIndex..<currentIndex]

      state.currentIndex = currentIndex

      return data
    }
  }

  /// Performs the ``write`` operation.
  public func write(contentsOf data: Data) throws {
    try access { state in
      guard !data.isEmpty else { return }

      let offset = state.data.distance(from: state.data.startIndex, to: state.currentIndex)
      let remaining = state.data.distance(from: state.currentIndex, to: state.data.endIndex)
      let replacedCount = min(data.count, remaining)
      let replacementEnd = state.data.index(state.currentIndex, offsetBy: replacedCount)
      state.data.replaceSubrange(state.currentIndex..<replacementEnd, with: data)
      state.currentIndex = state.data.index(state.data.startIndex, offsetBy: offset + data.count)
    }
  }

  /// Performs the ``close`` operation.
  public func close() throws {
    state.withLock { state in
      guard !state.closed else { return }
      state.closed = true
      state.currentIndex = state.data.endIndex
    }
  }

  /// The ``offset`` value.
  public var offset: Int {
    get throws {
      try access { state in
        return state.data.distance(from: state.data.startIndex, to: state.currentIndex)
      }
    }
  }

  /// Performs the ``setOffset`` operation.
  public func setOffset(_ offset: Int) throws {
    try access { state in

      guard offset >= 0, offset <= state.data.count else {
        throw Error.rangeCheck
      }

      state.currentIndex = state.data.index(state.data.startIndex, offsetBy: offset)
    }
  }

  /// The ``available`` value.
  public var available: Int {
    get throws {
      try access { state in
        return state.data.distance(from: state.currentIndex, to: state.data.endIndex)
      }
    }
  }

  /// The ``size`` value.
  public var size: Int {
    get throws {
      try access { state in
        return state.data.count
      }
    }
  }

  /// Performs the ``flush`` operation.
  public func flush() throws {
    try access { state in
      if mode == .read {
        state.currentIndex = state.data.endIndex
      }
    }
  }

  /// Performs the ``reset`` operation.
  public func reset() throws {
    // DataFile has no read-ahead or write-behind buffer to discard.
  }
}
