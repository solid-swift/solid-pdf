import SolidPostScript

protocol PDFGraphicsEventOutput: AnyObject {
  func process(_ event: GraphicsEvent) throws
  func beginImage(_ event: GraphicsEvent) throws
  func writeImageRows(_ rows: GraphicsImageRows) throws
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws
  func endImage() throws
  func abortImage()
}

final class PDFGraphicsClosureOutput: PDFGraphicsEventOutput {
  private let emit: (GraphicsEvent) throws -> Void

  init(emit: @escaping (GraphicsEvent) throws -> Void) {
    self.emit = emit
  }

  func process(_ event: GraphicsEvent) throws { try emit(event) }
  func beginImage(_ event: GraphicsEvent) throws { try emit(event) }
  func writeImageRows(_ rows: GraphicsImageRows) throws {}
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {}
  func endImage() throws {}
  func abortImage() {}
}

final class PDFGraphicsCollectorOutput: PDFGraphicsEventOutput {
  let collector = GraphicsEffectCollector()

  func process(_ event: GraphicsEvent) throws { collector.process(event) }
  func beginImage(_ event: GraphicsEvent) throws { try collector.beginImage(event) }
  func writeImageRows(_ rows: GraphicsImageRows) throws { try collector.writeImageRows(rows) }
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws { try collector.writeImageMaskRows(rows) }
  func endImage() throws { try collector.endImage() }
  func abortImage() { collector.abortImage() }
}
