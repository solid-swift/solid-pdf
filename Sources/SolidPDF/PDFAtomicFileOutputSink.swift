import Foundation

/// A same-directory atomic file sink.
public struct PDFAtomicFileOutputSink: PDFOutputSink, Sendable {
  /// The destination URL.
  public let destination: URL
  /// Whether an existing destination may be replaced.
  public let replacingExisting: Bool

  /// Creates an atomic file sink.
  public init(destination: URL, replacingExisting: Bool = false) {
    self.destination = destination
    self.replacingExisting = replacingExisting
  }

  public func makeSession() throws -> sending Session {
    try Session(destination: destination, replacingExisting: replacingExisting)
  }

  /// One atomic file-output session.
  public final class Session: PDFOutputSinkSession {
    private let destination: URL
    private let temporary: URL
    private let replacingExisting: Bool
    private var handle: FileHandle?
    private var finished = false

    fileprivate init(destination: URL, replacingExisting: Bool) throws {
      let manager = FileManager.default
      if manager.fileExists(atPath: destination.path), !replacingExisting {
        throw PDFError.outputExists
      }
      self.destination = destination
      self.replacingExisting = replacingExisting
      temporary = destination.deletingLastPathComponent().appendingPathComponent(
        ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
      )
      guard manager.createFile(atPath: temporary.path, contents: nil) else {
        throw PDFError.outputFailure
      }
      do { handle = try FileHandle(forWritingTo: temporary) }
      catch {
        try? manager.removeItem(at: temporary)
        throw PDFError.outputFailure
      }
    }

    deinit { if !finished { abort() } }

    public func write(_ data: borrowing Data) throws {
      guard !finished, let handle else { throw PDFError.writerFinished }
      do { try handle.write(contentsOf: data) }
      catch { throw PDFError.outputFailure }
    }

    public func finish(
      version: PDFVersion,
      pageCount: Int,
      diagnostics: [PDFDiagnostic]
    ) throws -> sending URL {
      guard !finished, let handle else { throw PDFError.writerFinished }
      do {
        try handle.synchronize()
        try handle.close()
        self.handle = nil
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
          guard replacingExisting else { throw PDFError.outputExists }
          try PDFFilePublisher.replace(destination, with: temporary)
        } else {
          try manager.moveItem(at: temporary, to: destination)
        }
        finished = true
        return destination
      } catch let error as PDFError {
        abort()
        throw error
      } catch {
        abort()
        throw PDFError.outputFailure
      }
    }

    public func abort() {
      guard !finished else { return }
      try? handle?.close()
      handle = nil
      try? FileManager.default.removeItem(at: temporary)
      finished = true
    }
  }
}
