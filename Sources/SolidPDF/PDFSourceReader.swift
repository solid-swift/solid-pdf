import Foundation

struct PDFSourceWindow: Sendable {
  let offset: Int64
  let data: Data

  var endOffset: Int64 { offset + Int64(data.count) }
}

actor PDFSourceReader<Session: PDFInputSourceSession> {
  private let session: Session
  private let byteCount: Int64
  private let windowByteCount: Int
  private let maximumCachedBytes: Int
  private var windows = [Int64: Data]()
  private var recency = [Int64]()
  private var cachedBytes = 0
  private var pending = [Int64: Task<Data, Error>]()
  private var closed = false

  init(session: Session, options: PDFParsingOptions) async throws {
    let limits = options.limits
    guard options.sourceWindowByteCount > 0,
      limits.maximumInputBytes >= 0,
      limits.maximumObjectCount > 0,
      limits.maximumNesting > 0,
      limits.maximumTokenBytes > 0,
      limits.maximumStringBytes >= 0,
      limits.maximumArrayElements >= 0,
      limits.maximumDictionaryEntries >= 0,
      limits.maximumDecodedStreamBytes >= 0,
      limits.maximumCachedSourceBytes >= options.sourceWindowByteCount,
      limits.maximumCachedObjectBytes >= 0,
      limits.maximumTailSearchBytes > 0
    else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "The parsing options contain invalid limits.")
      )
    }
    let byteCount = try await session.length()
    guard byteCount >= 0, byteCount <= limits.maximumInputBytes else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "The PDF input exceeds the configured size limit.")
      )
    }
    self.session = session
    self.byteCount = byteCount
    windowByteCount = options.sourceWindowByteCount
    maximumCachedBytes = limits.maximumCachedSourceBytes
  }

  func length() throws -> Int64 {
    guard !closed else { throw PDFParsingError.documentClosed }
    return byteCount
  }

  func window(containing position: Int64) async throws -> PDFSourceWindow? {
    guard !closed else { throw PDFParsingError.documentClosed }
    guard position >= 0, position <= byteCount else {
      throw PDFParsingError.sourceFailure(
        .init(offset: position, message: "The requested source position is outside the document.")
      )
    }
    guard position < byteCount else { return nil }
    let windowSize = Int64(windowByteCount)
    let start = (position / windowSize) * windowSize
    if let data = windows[start] {
      touch(start)
      return PDFSourceWindow(offset: start, data: data)
    }
    let task: Task<Data, Error>
    if let existing = pending[start] {
      task = existing
    } else {
      let length = Int(min(windowSize, byteCount - start))
      let range = PDFSourceRange(uncheckedOffset: start, length: length)
      let source = session
      task = Task { try await source.read(range) }
      pending[start] = task
    }
    do {
      let data = try await task.value
      pending[start] = nil
      let expected = Int(min(windowSize, byteCount - start))
      guard data.count == expected else {
        throw PDFParsingError.sourceFailure(
          .init(offset: start, message: "The input source returned a short range.")
        )
      }
      insert(data, at: start)
      return PDFSourceWindow(offset: start, data: data)
    } catch let error as PDFParsingError {
      pending[start] = nil
      throw error
    } catch is CancellationError {
      pending[start] = nil
      throw CancellationError()
    } catch {
      pending[start] = nil
      throw PDFParsingError.sourceFailure(
        .init(offset: start, message: "The input source read failed: \(error)")
      )
    }
  }

  func read(_ range: PDFSourceRange) async throws -> Data {
    guard !closed else { throw PDFParsingError.documentClosed }
    guard range.endOffset <= byteCount else {
      throw PDFParsingError.truncated(
        .init(offset: range.offset, message: "The requested source range is truncated.")
      )
    }
    var result = Data()
    result.reserveCapacity(range.length)
    var position = range.offset
    while position < range.endOffset {
      try Task.checkCancellation()
      guard let window = try await window(containing: position) else {
        throw PDFParsingError.truncated(
          .init(offset: position, message: "The requested source range is truncated.")
        )
      }
      let lower = Int(position - window.offset)
      let count = min(window.data.count - lower, Int(range.endOffset - position))
      result.append(window.data[lower..<(lower + count)])
      position += Int64(count)
    }
    return result
  }

  func close() async {
    guard !closed else { return }
    closed = true
    for task in pending.values { task.cancel() }
    pending.removeAll()
    windows.removeAll()
    recency.removeAll()
    cachedBytes = 0
    await session.close()
  }

  private func touch(_ offset: Int64) {
    recency.removeAll { $0 == offset }
    recency.append(offset)
  }

  private func insert(_ data: Data, at offset: Int64) {
    if windows[offset] == nil {
      windows[offset] = data
      cachedBytes += data.count
    }
    touch(offset)
    while cachedBytes > maximumCachedBytes, let oldest = recency.first {
      recency.removeFirst()
      if let removed = windows.removeValue(forKey: oldest) {
        cachedBytes -= removed.count
      }
    }
  }
}
