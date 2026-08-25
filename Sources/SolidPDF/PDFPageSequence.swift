/// A single-pass, explicitly closable sequence of PDF pages.
public final class PDFPageSequence: AsyncSequence, AsyncIteratorProtocol, Sendable {
  public typealias Element = PDFPage
  public typealias AsyncIterator = PDFPageSequence

  private let state: PDFPageSequenceState

  package init(state: PDFPageSequenceState) {
    self.state = state
  }

  deinit {
    let state = state
    Task { await state.close() }
  }

  public func makeAsyncIterator() -> PDFPageSequence { self }

  /// Returns the next page in document order.
  public func next() async throws -> PDFPage? {
    try await state.next()
  }

  /// Abandons traversal and releases sequence state.
  public func close() async {
    await state.close()
  }
}

package actor PDFPageSequenceState {
  typealias PageAt = @Sendable (Int) async throws -> PDFPage
  typealias Validate = @Sendable () async throws -> Int

  private let declaredCount: Int
  private let pageAt: PageAt
  private let validate: Validate
  private var index = 0
  private var closed = false

  init(declaredCount: Int, pageAt: @escaping PageAt, validate: @escaping Validate) {
    self.declaredCount = declaredCount
    self.pageAt = pageAt
    self.validate = validate
  }

  func next() async throws -> PDFPage? {
    guard !closed else { return nil }
    if index >= declaredCount {
      _ = try await validate()
      closed = true
      return nil
    }
    let page = try await pageAt(index)
    index += 1
    return page
  }

  func close() {
    closed = true
  }
}
