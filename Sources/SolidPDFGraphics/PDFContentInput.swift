import Foundation
import SolidPDF

final class PDFContentInput {
  struct Byte {
    let value: UInt8
    let streamIndex: Int
    let decodedOffset: Int64
  }

  private let streams: [PDFStreamObject]
  private let open: @Sendable (PDFStreamObject) async throws -> PDFDecodedStream
  private var streamIndex = 0
  private var active: PDFDecodedStream?
  private var chunk = Data()
  private var chunkIndex = 0
  private var lookahead: Byte?
  private var nextDecodedOffset: Int64 = 0
  private var closed = false

  init(
    streams: [PDFStreamObject],
    open: @escaping @Sendable (PDFStreamObject) async throws -> PDFDecodedStream
  ) {
    self.streams = streams
    self.open = open
  }

  func peek() async throws -> Byte? {
    if let lookahead { return lookahead }
    lookahead = try await readFromSource()
    return lookahead
  }

  func read() async throws -> Byte? {
    if let lookahead {
      self.lookahead = nil
      return lookahead
    }
    return try await readFromSource()
  }

  func close() async {
    guard !closed else { return }
    closed = true
    if let active { await active.close() }
    active = nil
    chunk.removeAll(keepingCapacity: false)
    lookahead = nil
  }

  func sourceSegment(from first: Byte, through last: Byte) -> [PDFContentSourceSegment] {
    guard first.streamIndex <= last.streamIndex else { return [] }
    var result: [PDFContentSourceSegment] = []
    for index in first.streamIndex...last.streamIndex {
      let stream = streams[index]
      let lower = index == first.streamIndex ? first.decodedOffset : decodedStart(of: index)
      let upper = index == last.streamIndex ? last.decodedOffset + 1 : decodedStart(of: index + 1)
      result.append(PDFContentSourceSegment(
        streamReference: stream.objectReference,
        encodedRange: stream.encodedRange,
        decodedOffset: lower,
        decodedLength: max(0, Int(upper - lower))
      ))
    }
    return result
  }

  private var decodedStarts: [Int64] = [0]

  private func decodedStart(of index: Int) -> Int64 {
    if index < decodedStarts.count { return decodedStarts[index] }
    return nextDecodedOffset
  }

  private func readFromSource() async throws -> Byte? {
    guard !closed else { return nil }
    while true {
      try Task.checkCancellation()
      if chunkIndex < chunk.count {
        let value = chunk[chunkIndex]
        chunkIndex += 1
        defer { nextDecodedOffset += 1 }
        return Byte(value: value, streamIndex: max(0, streamIndex - 1), decodedOffset: nextDecodedOffset)
      }
      if let active, let next = try await active.next() {
        guard !next.isEmpty else { continue }
        chunk = next
        chunkIndex = 0
        continue
      }
      if let active { await active.close() }
      self.active = nil
      chunk.removeAll(keepingCapacity: true)
      chunkIndex = 0
      guard streamIndex < streams.count else {
        closed = true
        return nil
      }
      if decodedStarts.count == streamIndex { decodedStarts.append(nextDecodedOffset) }
      active = try await open(streams[streamIndex])
      streamIndex += 1
    }
  }
}
