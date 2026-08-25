import Foundation

/// A single-pass sequence that concatenates a page's decoded content streams.
public final class PDFDecodedPageContent: AsyncSequence, AsyncIteratorProtocol, Sendable {
  public typealias Element = Data
  public typealias AsyncIterator = PDFDecodedPageContent

  private let state: PDFDecodedPageContentState

  package init(state: PDFDecodedPageContentState) {
    self.state = state
  }

  deinit {
    let state = state
    Task { await state.close() }
  }

  public func makeAsyncIterator() -> PDFDecodedPageContent { self }

  /// Returns the next nonempty content chunk without inserting separator bytes.
  public func next() async throws -> Data? {
    try await state.next()
  }

  /// Abandons content decoding and closes the active child stream.
  public func close() async {
    await state.close()
  }
}

package actor PDFDecodedPageContentState {
  typealias Open = @Sendable (PDFStreamObject) async throws -> PDFDecodedStream

  private let streams: [PDFStreamObject]
  private let maximumBytes: Int
  private let open: Open
  private var streamIndex = 0
  private var active: PDFDecodedStream?
  private var emittedBytes = 0
  private var closed = false

  init(streams: [PDFStreamObject], maximumBytes: Int, open: @escaping Open) {
    self.streams = streams
    self.maximumBytes = maximumBytes
    self.open = open
  }

  func next() async throws -> Data? {
    guard !closed else { return nil }
    do {
      while true {
        try Task.checkCancellation()
        if active == nil {
          guard streamIndex < streams.count else {
            closed = true
            return nil
          }
          active = try await open(streams[streamIndex])
          streamIndex += 1
        }
        guard let active else { continue }
        if let chunk = try await active.next() {
          guard !chunk.isEmpty else { continue }
          let (total, overflow) = emittedBytes.addingReportingOverflow(chunk.count)
          guard !overflow, total <= maximumBytes else {
            throw PDFParsingError.limitExceeded(
              .init(offset: 0, message: "Decoded page content exceeds its aggregate limit.")
            )
          }
          emittedBytes = total
          return chunk
        }
        await active.close()
        self.active = nil
      }
    } catch {
      await close()
      throw error
    }
  }

  func close() async {
    guard !closed else { return }
    closed = true
    if let active { await active.close() }
    active = nil
  }
}
