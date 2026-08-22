import Foundation

/// An immutable in-memory PDF input source.
public struct PDFDataInputSource: PDFInputSource, Sendable {
  public typealias Session = PDFDataInputSourceSession

  private let data: Data

  /// Creates an input source over immutable data.
  public init(_ data: Data) {
    self.data = data
  }

  public func makeSession() async throws -> sending PDFDataInputSourceSession {
    PDFDataInputSourceSession(data)
  }
}

/// A random-access session over immutable PDF data.
public final class PDFDataInputSourceSession: PDFInputSourceSession, @unchecked Sendable {
  private let data: Data

  fileprivate init(_ data: Data) {
    self.data = data
  }

  public func length() async throws -> Int64 {
    Int64(data.count)
  }

  public func read(_ range: PDFSourceRange) async throws -> Data {
    guard range.endOffset <= Int64(data.count) else {
      throw PDFParsingError.sourceFailure(
        .init(offset: range.offset, message: "The requested data range is unavailable.")
      )
    }
    let lower = Int(range.offset)
    return data.subdata(in: lower..<(lower + range.length))
  }

  public func close() async {}
}
