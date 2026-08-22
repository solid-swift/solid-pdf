/// Typed target output and metadata from one PDF graphics render.
public struct PDFGraphicsRenderResult<Output> {
  /// The target's completed output.
  public let output: Output
  /// Successfully transmitted source pages in output order.
  public let pages: [PDFRenderedPage]
  /// Nonfatal interpretation diagnostics.
  public let diagnostics: [PDFGraphicsDiagnostic]

  /// Creates a PDF graphics result.
  public init(output: Output, pages: [PDFRenderedPage], diagnostics: [PDFGraphicsDiagnostic]) {
    self.output = output
    self.pages = pages
    self.diagnostics = diagnostics
  }
}
