import SolidPDF
import SolidPostScript

final class PDFAnnotationEventOutput: PDFGraphicsEventOutput {
  private let base: PDFGraphicsEventOutput
  private let identifier: GraphicsResourceIdentifier

  init(base: PDFGraphicsEventOutput, annotation: PDFAnnotationIdentifier, revision: PDFRevisionIdentifier) {
    self.base = base
    identifier = GraphicsResourceIdentifier(
      rawValue: "pdf:r\(revision.ordinal):annotation:\(annotation.reference.objectNumber):\(annotation.reference.generationNumber)"
    )
  }

  func process(_ event: GraphicsEvent) throws { try base.process(decorated(event)) }
  func beginImage(_ event: GraphicsEvent) throws { try base.beginImage(decorated(event)) }
  func writeImageRows(_ rows: GraphicsImageRows) throws { try base.writeImageRows(rows) }
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws { try base.writeImageMaskRows(rows) }
  func endImage() throws { try base.endImage() }
  func abortImage() { base.abortImage() }

  private func decorated(_ event: GraphicsEvent) -> GraphicsEvent {
    GraphicsEvent(
      operation: event.operation,
      before: event.before,
      after: event.after,
      origin: GraphicsEventOrigin(resourceIdentifier: identifier, byteSegments: event.origin?.byteSegments ?? []),
      markedContentPath: event.markedContentPath,
      visibility: event.visibility
    )
  }
}
