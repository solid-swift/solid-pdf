//
//  Context+FileCursor.swift
//  SolidPostScript
//

import Foundation

extension Context {

  func readByte(from file: any File) async throws -> UInt8? {
    if let byte = takeReadAhead(max: 1, from: file).first {
      return byte
    }
    return try await readUnderlying(max: 1, from: file)?.first
  }

  func readByte(
    from file: any File,
    ifMatches predicate: (UInt8) -> Bool
  ) async throws -> (matched: UInt8?, eof: Bool) {
    guard let byte = try await readByte(from: file) else {
      return (nil, true)
    }
    guard predicate(byte) else {
      prependReadAhead(Data([byte]), to: file)
      return (nil, false)
    }
    return (byte, false)
  }

  func read(max: Int, from file: any File) async throws -> Data? {
    guard max >= 0 else { throw Error.rangeCheck }
    guard max > 0 else { return Data() }

    let buffered = takeReadAhead(max: max, from: file)
    guard buffered.isEmpty else { return buffered }
    guard let result = try await readUnderlying(max: max, from: file), !result.isEmpty else {
      return nil
    }
    return result
  }

  func available(in file: any File) async throws -> Int {
    let buffered = readAheadCount(for: file)
    let underlying: Int
    if let contextual = file as? any ContextualFile {
      underlying = try await contextual.available(context: self)
    } else {
      underlying = try file.available
    }
    guard underlying >= 0 else {
      return buffered > 0 ? buffered : underlying
    }
    let (available, overflow) = buffered.addingReportingOverflow(underlying)
    return overflow ? .max : available
  }

  func logicalOffset(in file: any File) throws -> Int {
    try file.offset - readAheadCount(for: file)
  }

  func setLogicalOffset(_ offset: Int, in file: any File) throws {
    try file.setOffset(offset)
    clearReadAhead(for: file)
  }

  func reset(file: any File) throws {
    clearReadAhead(for: file)
    try file.reset()
  }

  func closeLogicalFile(_ file: any File) async throws {
    clearReadAhead(for: file)
    if let contextual = file as? any ContextualFile {
      try await contextual.close(context: self)
    } else {
      try file.close()
    }
  }

  func flushLogicalFile(_ file: any File) async throws {
    clearReadAhead(for: file)
    if let contextual = file as? any ContextualFile {
      try await contextual.flush(context: self)
    } else {
      try file.flush()
    }
  }

  func prependReadAhead(_ data: Data, to file: any File) {
    guard !data.isEmpty else { return }
    let identifier = ObjectIdentifier(file)
    let existing = fileReadAhead[identifier]?.data ?? Data()
    fileReadAhead[identifier] = FileReadAhead(file: file, data: data + existing)
  }

  func clearReadAhead(for file: any File) {
    fileReadAhead.removeValue(forKey: ObjectIdentifier(file))
  }

  private func readUnderlying(max: Int, from file: any File) async throws -> Data? {
    if let contextual = file as? any ContextualFile {
      return try await contextual.read(max: max, context: self)
    }
    return try file.read(max: max)
  }

  private func takeReadAhead(max: Int, from file: any File) -> Data {
    let identifier = ObjectIdentifier(file)
    guard var entry = fileReadAhead[identifier], entry.file === file, !entry.data.isEmpty else {
      fileReadAhead.removeValue(forKey: identifier)
      return Data()
    }
    let count = min(max, entry.data.count)
    let result = Data(entry.data.prefix(count))
    entry.data.removeFirst(count)
    if entry.data.isEmpty {
      fileReadAhead.removeValue(forKey: identifier)
    } else {
      fileReadAhead[identifier] = entry
    }
    return result
  }

  private func readAheadCount(for file: any File) -> Int {
    guard let entry = fileReadAhead[ObjectIdentifier(file)], entry.file === file else { return 0 }
    return entry.data.count
  }

}
