import SolidPostScript

final class PDFGraphicsRendererOutput<Renderer: GraphicsRenderer>: PDFGraphicsEventOutput {
  let renderer: Renderer
  private(set) var imageActive = false

  init(renderer: Renderer) {
    self.renderer = renderer
  }

  func process(_ event: GraphicsEvent) throws {
    try target { try renderer.process(event) }
  }

  func beginImage(_ event: GraphicsEvent) throws {
    try target { try renderer.beginImage(event) }
    imageActive = true
  }

  func writeImageRows(_ rows: GraphicsImageRows) throws {
    try target { try renderer.writeImageRows(rows) }
  }

  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
    try target { try renderer.writeImageMaskRows(rows) }
  }

  func endImage() throws {
    try target { try renderer.endImage() }
    imageActive = false
  }

  func abortImage() {
    guard imageActive else { return }
    imageActive = false
    renderer.abortImage()
  }

  private func target(_ body: () throws -> Void) throws {
    do { try body() } catch { throw PDFGraphicsError.targetFailure(String(describing: error)) }
  }
}
