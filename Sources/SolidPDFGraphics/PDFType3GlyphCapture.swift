import SolidPostScript

final class PDFType3GlyphCapture {
  enum Mode: Sendable, Hashable {
    case colorized
    case uncolored
  }

  let location: PDFContentLocation
  private(set) var mode: Mode?
  private(set) var metrics: GraphicsGlyphMetrics?

  init(location: PDFContentLocation) {
    self.location = location
  }

  func establish(
    mode: Mode,
    metrics: GraphicsGlyphMetrics,
    instruction: PDFContentInstruction
  ) throws {
    guard self.metrics == nil else {
      throw PDFGraphicsError.malformedContent(
        message: "Type 3 CharProc repeats d0 or d1.",
        operatorName: instruction.name,
        location: instruction.location
      )
    }
    self.mode = mode
    self.metrics = metrics
  }
}
