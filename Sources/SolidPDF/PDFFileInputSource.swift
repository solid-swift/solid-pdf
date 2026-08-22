import Foundation

/// A file-backed random-access PDF input source.
public struct PDFFileInputSource: PDFInputSource, Sendable {
  public typealias Session = PDFFileInputSourceSession

  /// The file URL opened by each session.
  public let url: URL

  /// Creates a file-backed source.
  public init(url: URL) {
    self.url = url
  }

  public func makeSession() async throws -> sending PDFFileInputSourceSession {
    try PDFFileInputSourceSession(url: url)
  }
}

/// An actor-isolated random-access file session.
public actor PDFFileInputSourceSession: PDFInputSourceSession {
  private var handle: FileHandle?
  private let byteCount: Int64

  fileprivate init(url: URL) throws {
    let handle = try FileHandle(forReadingFrom: url)
    self.handle = handle
    byteCount = Int64(try handle.seekToEnd())
  }

  deinit {
    try? handle?.close()
  }

  public func length() async throws -> Int64 {
    guard handle != nil else { throw PDFParsingError.documentClosed }
    return byteCount
  }

  public func read(_ range: PDFSourceRange) async throws -> Data {
    guard let handle else { throw PDFParsingError.documentClosed }
    guard range.endOffset <= byteCount else {
      throw PDFParsingError.sourceFailure(
        .init(offset: range.offset, message: "The requested file range is unavailable.")
      )
    }
    do {
      try handle.seek(toOffset: UInt64(range.offset))
      let data = try handle.read(upToCount: range.length) ?? Data()
      guard data.count == range.length else {
        throw PDFParsingError.sourceFailure(
          .init(offset: range.offset, message: "The file returned a short read.")
        )
      }
      return data
    } catch let error as PDFParsingError {
      throw error
    } catch {
      throw PDFParsingError.sourceFailure(
        .init(offset: range.offset, message: "The file read failed: \(error)")
      )
    }
  }

  public func close() async {
    try? handle?.close()
    handle = nil
  }
}
