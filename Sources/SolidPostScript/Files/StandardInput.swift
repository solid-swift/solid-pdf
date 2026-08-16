//
//  StandardInput.swift
//

import Foundation
import SolidIO
import Synchronization

actor StandardInputChannel {

  private let source: any Source
  private var buffered = Data()
  private var reachedEnd = false

  init(source: any Source) {
    self.source = source
  }

  func read(max: Int) async throws -> Data? {
    guard max >= 0 else { throw Error.rangeCheck }
    guard max > 0 else { return Data() }

    do {
      if buffered.isEmpty, !reachedEnd {
        try Task<Never, Never>.checkCancellation()
        guard let data = try await source.read(max: max) else {
          reachedEnd = true
          return nil
        }
        buffered.append(data)
      }

      guard !buffered.isEmpty else { return nil }
      let count = min(max, buffered.count)
      let result = Data(buffered.prefix(count))
      buffered.removeFirst(count)
      return result
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Error.ioError
    }
  }

  func unread(_ byte: UInt8) {
    buffered.insert(byte, at: buffered.startIndex)
  }

  func flush() async throws {
    while try await read(max: 4096) != nil {}
  }

  var available: Int { buffered.count }
}

struct StandardInputFileDevice: FileDevice {
  let channel: StandardInputChannel

  var searched: Bool { false }
  var name: String { "stdin" }

  func open(name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> any File {
    guard name.isEmpty, mode == .read, openMethod == .existingOnly else {
      throw Error.invalidFileAccess
    }
    return StandardInputFile(channel: channel)
  }
}

final class StandardInputFile: ContextualFile, Sendable {

  private let channel: StandardInputChannel
  private let closed = Mutex(false)

  let name = "stdin"
  let mode: Mode = .read
  let isPositionable = false

  init(channel: StandardInputChannel) {
    self.channel = channel
  }

  var isClosed: Bool { closed.withLock { $0 } }

  func readByte() throws -> UInt8? { throw Error.ioError }

  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    throw Error.ioError
  }

  func read(max: Int) throws -> Data? { throw Error.ioError }

  func read(max: Int, context: isolated Context) async throws -> Data? {
    try checkOpen()
    return try await context.withUserTimeSuspended {
      try await channel.read(max: max)
    }
  }

  func readByte(context: isolated Context) async throws -> UInt8? {
    try await read(max: 1, context: context)?.first
  }

  func readByte(
    ifMatches predicate: (UInt8) -> Bool,
    context: isolated Context
  ) async throws -> (matched: UInt8?, eof: Bool) {
    guard let byte = try await readByte(context: context) else { return (nil, true) }
    guard predicate(byte) else {
      await channel.unread(byte)
      return (nil, false)
    }
    return (byte, false)
  }

  func write(contentsOf data: Data) throws { throw Error.ioError }

  func close() {
    closed.withLock { $0 = true }
  }

  func close(context: isolated Context) async { close() }

  var offset: Int { get throws { throw Error.ioError } }
  func setOffset(_ offset: Int) throws { throw Error.ioError }
  var available: Int { get throws { throw Error.ioError } }

  func available(context: isolated Context) async throws -> Int {
    try checkOpen()
    return await channel.available
  }

  var size: Int { get throws { throw Error.ioError } }

  func flush() throws { throw Error.ioError }

  func flush(context: isolated Context) async throws {
    try checkOpen()
    try await context.withUserTimeSuspended {
      try await channel.flush()
    }
  }

  func reset() {}

  private func checkOpen() throws {
    guard !isClosed else { throw Error.ioError }
  }
}
