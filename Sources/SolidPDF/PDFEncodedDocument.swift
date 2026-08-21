import Foundation

/// A completed deterministic in-memory PDF document.
public struct PDFEncodedDocument: Sendable, Hashable {
  /// The encoded bytes.
  public let data: Data
  /// The emitted PDF version.
  public let version: PDFVersion
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
    self.pageCount = pageCount
    self.diagnostics = diagnostics
  }
}
