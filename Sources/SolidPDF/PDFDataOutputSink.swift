import Foundation

/// An in-memory PDF output sink.
public struct PDFDataOutputSink: PDFOutputSink, Sendable {
  /// Creates a data sink.
  public init() {}

  public func makeSession() -> sending Session { Session() }

  /// One in-memory output session.
  public final class Session: PDFOutputSinkSession {
    private var data = Data()
    private var finished = false

    public func write(_ data: borrowing Data) throws {
      guard !finished else { throw PDFError.writerFinished }
      self.data.append(data)
    }

    public func finish(
      version: PDFVersion,
      pageCount: Int,
      diagnostics: [PDFDiagnostic]
    ) throws -> sending PDFEncodedDocument {
      guard !finished else { throw PDFError.writerFinished }
      finished = true
      return PDFEncodedDocument(
        data: data,
        version: version,
        pageCount: pageCount,
        diagnostics: diagnostics
      )
    }

    public func finishIncrementalUpdate(
      fileVersion: PDFFileVersion,
      pageCount: Int,
      diagnostics: [PDFDiagnostic]
    ) throws -> sending PDFEncodedDocument {
      guard !finished else { throw PDFError.writerFinished }
      finished = true
      return PDFEncodedDocument(
        data: data,
        version: fileVersion == .v2_0 ? .v2_0 : .v1_7,
        pageCount: pageCount,
        diagnostics: diagnostics,
        fileVersion: fileVersion
      )
    }

    public func abort() {
      data.removeAll(keepingCapacity: false)
      finished = true
    }
  }
}
