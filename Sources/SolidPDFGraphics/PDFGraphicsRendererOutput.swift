import SolidPostScript

final class PDFGraphicsRendererOutput<Renderer: GraphicsRenderer>: PDFGraphicsEventOutput {
  let renderer: Renderer
  private(set) var imageActive = false
  private var imageSuppressed = false

  init(renderer: Renderer) {
    self.renderer = renderer
  }

  func process(_ event: GraphicsEvent) throws {
    if !event.visibility.isVisible, !renderer.preservesHiddenSemanticContent,
      case .paint = event.operation
    { return }
    try target { try renderer.process(event) }
  }

  func beginImage(_ event: GraphicsEvent) throws {
    if !event.visibility.isVisible, !renderer.preservesHiddenSemanticContent {
      imageSuppressed = true
      imageActive = true
      return
    }
    try target { try renderer.beginImage(event) }
    imageActive = true
  }

  func writeImageRows(_ rows: GraphicsImageRows) throws {
    if imageSuppressed { return }
    try target { try renderer.writeImageRows(rows) }
  }

  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
    if imageSuppressed { return }
    try target { try renderer.writeImageMaskRows(rows) }
  }

  func endImage() throws {
    if imageSuppressed {
      imageSuppressed = false
      imageActive = false
      return
    }
    try target { try renderer.endImage() }
    imageActive = false
  }

  func abortImage() {
    guard imageActive else { return }
    imageActive = false
    if imageSuppressed {
      imageSuppressed = false
      return
    }
    renderer.abortImage()
  }

  private func target(_ body: () throws -> Void) throws {
    do { try body() } catch { throw PDFGraphicsError.targetFailure(String(describing: error)) }
  }
}
