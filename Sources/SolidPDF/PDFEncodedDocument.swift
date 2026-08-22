import Foundation

/// A completed deterministic in-memory PDF document.
public struct PDFEncodedDocument: Sendable, Hashable {
  /// The encoded bytes.
  public let data: Data
  /// The emitted PDF version.
  public let version: PDFVersion
  /// The exact inherited file version for an incremental update, when applicable.
  public let fileVersion: PDFFileVersion?
  /// The number of page objects in the document.
  public let pageCount: Int
  /// Nonfatal diagnostics collected during construction.
  public let diagnostics: [PDFDiagnostic]

  /// Creates an encoded document.
  public init(
    data: Data,
    version: PDFVersion,
    pageCount: Int,
    diagnostics: [PDFDiagnostic] = []
  ) {
    self.data = data
    self.version = version
    fileVersion = nil
    self.pageCount = pageCount
    self.diagnostics = diagnostics
  }

  /// Creates an encoded incremental document retaining its exact inherited version.
  public init(
    data: Data,
    version: PDFVersion,
    pageCount: Int,
    diagnostics: [PDFDiagnostic],
    fileVersion: PDFFileVersion
  ) {
    self.data = data
    self.version = version
    self.fileVersion = fileVersion
    self.pageCount = pageCount
    self.diagnostics = diagnostics
  }
}
