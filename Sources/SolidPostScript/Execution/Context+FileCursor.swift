//
//  Context+FileCursor.swift
//  SolidPostScript
//

import Foundation

extension Context {

  func readByte(from file: any File) async throws -> UInt8? {
    if let byte = takeReadAhead(max: 1, from: file).first {
      try await finishPendingEndOfFileIfDrained(from: file)
      return byte
    }
    if hasPendingEndOfFile(for: file) {
      try await finishPendingEndOfFile(from: file)
      return nil
    }
    guard !file.isClosed else { return nil }
    guard let data = try await readUnderlying(max: 1, from: file), !data.isEmpty else {
      try await encounteredEndOfFile(in: file)
      return nil
    }
    if data.count > 1 {
      prependReadAhead(Data(data.dropFirst()), to: file)
    }
    return data.first
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

    var result = takeReadAhead(max: max, from: file)
    if hasPendingEndOfFile(for: file), readAheadCount(for: file) == 0 {
      try await finishPendingEndOfFile(from: file)
      return result.isEmpty ? nil : result
    }
    while result.count < max, !file.isClosed {
      let remaining = max - result.count
      guard let data = try await readUnderlying(max: remaining, from: file), !data.isEmpty else {
        try await encounteredEndOfFile(in: file)
        break
      }

      let consumed = min(remaining, data.count)
      result.append(data.prefix(consumed))
      if consumed < data.count {
        prependReadAhead(Data(data.dropFirst(consumed)), to: file)
      }
    }

    try await finishPendingEndOfFileIfDrained(from: file)

    return result.isEmpty ? nil : result
  }

  func readScannerByte(from file: any File) async throws -> UInt8? {
    if let byte = takeReadAhead(max: 1, from: file).first {
      try await finishPendingEndOfFileIfDrained(from: file)
      return byte
    }
    if hasPendingEndOfFile(for: file) {
      try await finishPendingEndOfFile(from: file)
      return nil
    }
    guard !file.isClosed else { return nil }
    guard let data = try await readUnderlying(max: 1, from: file), !data.isEmpty else {
      filePendingEndOfFile[ObjectIdentifier(file)] = file
      return nil
    }
    if data.count > 1 {
      prependReadAhead(Data(data.dropFirst()), to: file)
    }
    return data.first
  }

  func finishScannerRead(from file: any File) async throws {
    try await finishPendingEndOfFileIfDrained(from: file)
  }

  func available(in file: any File) async throws -> Int {
    let buffered = readAheadCount(for: file)
    if buffered == 0, hasPendingEndOfFile(for: file) {
      try await finishPendingEndOfFile(from: file)
      return -1
    }
    if file.isClosed {
      return buffered > 0 ? buffered : -1
    }
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
    clearPendingEndOfFile(for: file)
  }

  func reset(file: any File) throws {
    clearReadAhead(for: file)
    clearPendingEndOfFile(for: file)
    try file.reset()
  }

  func closeLogicalFile(_ file: any File) async throws {
    clearReadAhead(for: file)
    clearPendingEndOfFile(for: file)
    guard !file.isClosed else { return }
    if let contextual = file as? any ContextualFile {
      try await contextual.close(context: self)
    } else {
      try file.close()
    }
  }

  func flushLogicalFile(_ file: any File) async throws {
    clearReadAhead(for: file)
    clearPendingEndOfFile(for: file)
    guard !file.isClosed else { return }
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

  func readLine(max: Int, from file: any File) async throws -> (line: Data, eof: Bool) {
    guard max > 0 else { throw Error.rangeCheck }

    var line = Data(capacity: max)
    while true {
      guard let byte = try await readByte(from: file) else {
        return (line, true)
      }

      if byte == Scanner.lineFeed {
        return (line, false)
      }
      if byte == Scanner.carriageReturn {
        _ = try await readByte(from: file, ifMatches: { $0 == Scanner.lineFeed })
        return (line, false)
      }

      line.append(byte)
      guard line.count < max else { throw Error.rangeCheck }
    }
  }

  private func readUnderlying(max: Int, from file: any File) async throws -> Data? {
    if let contextual = file as? any ContextualFile {
      return try await contextual.read(max: max, context: self)
    }
    return try file.read(max: max)
  }

  private func encounteredEndOfFile(in file: any File) async throws {
    guard file.closesAtEndOfFile, !file.isClosed else { return }
    try await closeLogicalFile(file)
  }

  private func hasPendingEndOfFile(for file: any File) -> Bool {
    filePendingEndOfFile[ObjectIdentifier(file)] === file
  }

  private func clearPendingEndOfFile(for file: any File) {
    let identifier = ObjectIdentifier(file)
    guard filePendingEndOfFile[identifier] === file else { return }
    filePendingEndOfFile.removeValue(forKey: identifier)
  }

  private func finishPendingEndOfFileIfDrained(from file: any File) async throws {
    guard readAheadCount(for: file) == 0, hasPendingEndOfFile(for: file) else { return }
    try await finishPendingEndOfFile(from: file)
  }

  private func finishPendingEndOfFile(from file: any File) async throws {
    clearPendingEndOfFile(for: file)
    try await encounteredEndOfFile(in: file)
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
