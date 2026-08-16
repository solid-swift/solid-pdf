//
//  DeviceFile.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation
import Synchronization

/// A synchronous, seekable operating-system file.
public final class OSFile: File, Sendable {

  /// The ``name`` value.
  public let name: String
  /// The ``mode`` value.
  public let mode: Mode
  /// The ``openMethod`` value.
  public let openMethod: FileOpenMethod

  private let state: Mutex<FileHandle?>

  /// Creates an instance.
  public convenience init(name: String, mode: Mode, openMethod: FileOpenMethod) throws {
    let (handle, mode) =
      switch (mode, openMethod) {
      case (.read, .existingOnly): try Self.openExistingForRead(fileName: name)
      case (.write, .truncateOrCreate): try Self.openNewForWrite(fileName: name)
      case (.write, .appendExistingOrCreate): try Self.openForWrite(fileName: name)
      case (.readWrite, .existingOnly): try Self.openExistingForReadWrite(fileName: name)
      case (.readWrite, .truncateOrCreate): try Self.openNewForReadWrite(fileName: name)
      case (.readWrite, .appendExistingOrCreate): try Self.openForReadWrite(fileName: name)
      default: throw Error.invalidFileAccess
      }

    self.init(handle: handle, name: name, mode: mode, openMethod: openMethod)
  }

  /// Creates an instance.
  public init(handle: FileHandle, name: String, mode: Mode, openMethod: FileOpenMethod) {
    self.state = Mutex(handle)
    self.name = name
    self.mode = mode
    self.openMethod = openMethod
  }

  private func access<U>(block: (FileHandle) throws -> U) throws -> U {
    try state.withLock { state in
      guard let handle = state else {
        throw Error.ioError
      }
      return try block(handle)
    }
  }

  /// The ``isClosed`` value.
  public var isClosed: Bool {
    state.withLock { $0 == nil }
  }

  /// Performs the ``close`` operation.
  public func close() throws {
    internalClose()
  }

  private func internalClose() {
    state.withLock { state in
      guard let handle = state else { return }
      do { try handle.close() } catch {}
      state = nil
    }
  }

  /// The ``offset`` value.
  public var offset: Int {
    get throws {
      try access { state in
        return Int(try state.offset())
      }
    }
  }

  /// Performs the ``setOffset`` operation.
  public func setOffset(_ offset: Int) throws {
    guard offset >= 0 else {
      throw Error.rangeCheck
    }
    try access { state in
      do {
        try state.seek(toOffset: UInt64(offset))
      } catch {
        throw Error.ioError
      }
    }
  }

  /// The ``available`` value.
  public var available: Int {
    get throws {
      try access { state in
        do {
          let offset = try state.offset()
          let size = try state.size()
          return Int(size - offset)
        } catch {
          throw Error.ioError
        }
      }
    }
  }

  /// The ``size`` value.
  public var size: Int {
    get throws {
      try access { state in
        do {
          return Int(try state.size())
        } catch {
          throw Error.ioError
        }
      }
    }
  }

  /// Performs the ``readByte`` operation.
  public func readByte() throws -> UInt8? {
    return try read(max: 1)?.first
  }

  /// Performs the ``readByte`` operation.
  public func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    try state.withLock { state in
      guard let byte = try read(max: 1, state: &state)?.first else {
        return (nil, true)
      }

      guard predicate(byte) else {
        guard let handle = state else {
          throw Error.ioError
        }
        let currentOffset = try handle.offset()
        try handle.seek(toOffset: currentOffset - 1)
        return (nil, false)
      }

      return (byte, false)
    }
  }

  /// Performs the ``read`` operation.
  public func read(max: Int) throws -> Data? {
    try state.withLock { try read(max: max, state: &$0) }
  }

  /// Performs the ``write`` operation.
  public func write(contentsOf data: Data) throws {
    try access { state in
      do {
        try state.write(contentsOf: data)
      } catch {
        throw Error.ioError
      }
    }
  }

  /// Performs the ``flush`` operation.
  public func flush() throws {
    try access { state in
      do {
        if mode == .read {
          try state.seekToEnd()
        } else {
          try state.synchronize()
        }
      } catch {
        throw Error.ioError
      }
    }
  }

  /// Performs the ``reset`` operation.
  public func reset() throws {
    // FileHandle exposes no read-ahead or write-behind buffer to discard.
  }

  private func read(max: Int, state: inout FileHandle?) throws -> Data? {
    guard let handle = state else {
      return nil
    }

    do {
      let result = try handle.read(upToCount: max)
      if result == nil {
        try? handle.close()
        state = nil
      }
      return result
    } catch {
      throw Error.ioError
    }
  }

  private static func openExistingForRead(fileName: String) throws -> (FileHandle, Mode) {
    do {
      return (try FileHandle(forReadingFrom: URL(fileURLWithPath: fileName)), .read)
    } catch {
      throw FileSystemErrorTranslation.translate(error)
    }
  }

  private static func openNewForWrite(fileName: String) throws -> (FileHandle, Mode) {
    let url = URL(fileURLWithPath: fileName)
    do {
      try Data().write(to: url)
      return (try FileHandle(forWritingTo: url), .write)
    } catch {
      throw FileSystemErrorTranslation.translate(error)
    }
  }

  private static func openForWrite(fileName: String) throws -> (FileHandle, Mode) {
    do {
      let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: fileName))
      try handle.seekToEnd()
      return (handle, .write)
    } catch {
      guard FileSystemErrorTranslation.translate(error) == .undefinedFilename else {
        throw FileSystemErrorTranslation.translate(error)
      }
      return try openNewForWrite(fileName: fileName)
    }
  }

  private static func openExistingForReadWrite(fileName: String) throws -> (FileHandle, Mode) {
    do {
      return (try FileHandle(forUpdating: URL(fileURLWithPath: fileName)), .readWrite)
    } catch {
      throw FileSystemErrorTranslation.translate(error)
    }
  }

  private static func openNewForReadWrite(fileName: String) throws -> (FileHandle, Mode) {
    let url = URL(fileURLWithPath: fileName)
    do {
      try Data().write(to: url)
      return (try FileHandle(forUpdating: url), .readWrite)
    } catch {
      throw FileSystemErrorTranslation.translate(error)
    }
  }

  private static func openForReadWrite(fileName: String) throws -> (FileHandle, Mode) {
    do {
      let handle = try FileHandle(forUpdating: URL(fileURLWithPath: fileName))
      try handle.seekToEnd()
      return (handle, .readWrite)
    } catch {
      guard FileSystemErrorTranslation.translate(error) == .undefinedFilename else {
        throw FileSystemErrorTranslation.translate(error)
      }
      return try openNewForReadWrite(fileName: fileName)
    }
  }
}

extension FileHandle {

  fileprivate func size() throws -> UInt64 {
    let offset = try offset()
    let size = try seekToEnd()
    try seek(toOffset: offset)
    return size
  }

}
