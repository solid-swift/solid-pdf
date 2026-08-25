import Foundation

/// A single-pass asynchronous sequence of decoded PDF stream bytes.
public final class PDFDecodedStream: AsyncSequence, AsyncIteratorProtocol, Sendable {
  public typealias Element = Data
  public typealias AsyncIterator = PDFDecodedStream

  private let state: any PDFDecodedStreamState

  package init(state: any PDFDecodedStreamState) {
    self.state = state
  }

  deinit {
    let state = state
    Task { await state.close() }
  }

  /// Returns this single-pass stream as its iterator.
  public func makeAsyncIterator() -> PDFDecodedStream {
    self
  }

  /// Returns the next nonempty decoded chunk, or `nil` after completion.
  public func next() async throws -> Data? {
    try await state.next()
  }

  /// Abandons decoding and releases its source and scratch storage.
  public func close() async {
    await state.close()
  }
}

package protocol PDFDecodedStreamState: Actor, Sendable {
  func next() async throws -> Data?
  func close() async
}
