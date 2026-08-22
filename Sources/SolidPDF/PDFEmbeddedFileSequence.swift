/// A single-pass, explicitly closable sequence of embedded-file descriptors.
public final class PDFEmbeddedFileSequence: AsyncSequence, AsyncIteratorProtocol, Sendable {
  public typealias Element = PDFEmbeddedFile
  public typealias AsyncIterator = PDFEmbeddedFileSequence

  private let state: PDFEmbeddedFileSequenceState

  package init(files: [PDFEmbeddedFile]) {
    state = PDFEmbeddedFileSequenceState(files: files)
  }

  deinit {
    let state = state
    Task { await state.close() }
  }

  public func makeAsyncIterator() -> PDFEmbeddedFileSequence { self }

  /// Returns the next descriptor in deterministic name-tree order.
  public func next() async throws -> PDFEmbeddedFile? {
    try await state.next()
  }

  /// Ends enumeration and releases retained descriptors.
  public func close() async {
    await state.close()
  }
}

private actor PDFEmbeddedFileSequenceState {
  private var files: [PDFEmbeddedFile]
  private var index = 0
  private var closed = false

  init(files: [PDFEmbeddedFile]) {
    self.files = files
  }

  func next() throws -> PDFEmbeddedFile? {
    guard !closed else { return nil }
    try Task.checkCancellation()
    guard index < files.count else {
      close()
      return nil
    }
    defer { index += 1 }
    return files[index]
  }

  func close() {
    closed = true
    files.removeAll(keepingCapacity: false)
  }
}
