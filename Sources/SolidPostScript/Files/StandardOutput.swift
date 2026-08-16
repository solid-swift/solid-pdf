//
//  StandardOutput.swift
//

import Foundation
import SolidIO
import Synchronization

actor StandardOutputChannel {

  private let sink: any Sink
  private var writing = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(sink: any Sink) {
    self.sink = sink
  }

  func write(_ data: Data) async throws {
    guard !data.isEmpty else { return }
    await acquire()
    defer { release() }

    do {
      try Task<Never, Never>.checkCancellation()
      try await sink.write(data: data)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Error.ioError
    }
  }

  func flush() async throws {
    await acquire()
    defer { release() }

    do {
      try Task<Never, Never>.checkCancellation()
      if let flushable = sink as? any Sink & Flushable {
        try await flushable.flush()
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Error.ioError
    }
  }

  private func acquire() async {
    guard writing else {
      writing = true
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func release() {
    guard !waiters.isEmpty else {
      writing = false
      return
    }
    waiters.removeFirst().resume()
  }
}

struct StandardOutputFileDevice: FileDevice {
  let channel: StandardOutputChannel
  let deviceName: String

  var searched: Bool { false }
  var name: String { deviceName }

  func open(name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> any File {
    guard name.isEmpty, mode == .write, openMethod == .truncateOrCreate else {
      throw Error.invalidFileAccess
    }
    return StandardOutputFile(channel: channel, name: deviceName)
  }
}

final class StandardOutputFile: ContextualFile, Sendable {

  private let channel: StandardOutputChannel
  private let closed = Mutex(false)

  let name: String
  let mode: Mode = .write
  let isPositionable = false

  init(channel: StandardOutputChannel, name: String = "stdout") {
    self.channel = channel
    self.name = name
  }

  var isClosed: Bool { closed.withLock { $0 } }

  func readByte() throws -> UInt8? { throw Error.ioError }

  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    throw Error.ioError
  }

  func read(max: Int) throws -> Data? { throw Error.ioError }

  func readByte(context: isolated Context) async throws -> UInt8? { throw Error.ioError }

  func readByte(
    ifMatches predicate: (UInt8) -> Bool,
    context: isolated Context
  ) async throws -> (matched: UInt8?, eof: Bool) {
    throw Error.ioError
  }

  func read(max: Int, context: isolated Context) async throws -> Data? { throw Error.ioError }

  func available(context: isolated Context) async throws -> Int { throw Error.ioError }

  func write(contentsOf data: Data) throws { throw Error.ioError }

  func write(contentsOf data: Data, context: isolated Context) async throws {
    try checkOpen()
    try await channel.write(data)
  }

  func close() {
    closed.withLock { $0 = true }
  }

  func close(context: isolated Context) async {
    close()
  }

  var offset: Int { get throws { throw Error.ioError } }
  func setOffset(_ offset: Int) throws { throw Error.ioError }
  var available: Int { get throws { throw Error.ioError } }
  var size: Int { get throws { throw Error.ioError } }

  func flush() throws { throw Error.ioError }

  func flush(context: isolated Context) async throws {
    try checkOpen()
    try await channel.flush()
  }

  func reset() {}

  private func checkOpen() throws {
    guard !isClosed else { throw Error.ioError }
  }
}
