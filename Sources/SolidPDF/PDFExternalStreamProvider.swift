/// Explicit authority for opening stream data referenced by a PDF `/F` entry.
public protocol PDFExternalStreamProvider: Sendable {
  /// Opens an isolated random-access session for a resolved PDF file specification.
  ///
  /// The provider owns path interpretation and confinement. SolidPDF never opens a host path implicitly.
  func open(
    _ fileSpecification: PDFObject,
    for stream: PDFStreamObject
  ) async throws -> any PDFInputSourceSession
}
