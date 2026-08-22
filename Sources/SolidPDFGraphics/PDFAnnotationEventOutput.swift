import Foundation
import SolidPDF
import SolidPostScript

final class PDFAnnotationEventOutput: PDFGraphicsEventOutput {
  private let base: PDFGraphicsEventOutput
  private let identifier: GraphicsResourceIdentifier
  private let scope: GraphicsMarkedContentScope
  private var imageState: GraphicsStateSnapshot?

  init(
    base: PDFGraphicsEventOutput,
    annotation: PDFAnnotationIdentifier,
    revision: PDFRevisionIdentifier,
    visibility: GraphicsContentVisibility = .visible
  ) {
    self.base = base
    identifier = GraphicsResourceIdentifier(
      rawValue: "pdf:r\(revision.ordinal):annotation:\(annotation.reference.objectNumber):\(annotation.reference.generationNumber)"
    )
    scope = GraphicsMarkedContentScope(
      resourceIdentifier: identifier,
      tag: Data("Annotation".utf8),
      visibility: visibility
    )
  }

  func process(_ event: GraphicsEvent) throws {
    if case .content(.markedContent) = event.operation {
      try base.process(decorated(event))
      return
    }
    try base.process(boundary(.begin(scope), state: event.before))
    try base.process(decorated(event))
    try base.process(boundary(.end(scope), state: event.after))
  }

  func beginImage(_ event: GraphicsEvent) throws {
    imageState = event.before
    try base.process(boundary(.begin(scope), state: event.before))
    try base.beginImage(decorated(event))
  }
  func writeImageRows(_ rows: GraphicsImageRows) throws { try base.writeImageRows(rows) }
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws { try base.writeImageMaskRows(rows) }
  func endImage() throws {
    try base.endImage()
    if let state = imageState { try base.process(boundary(.end(scope), state: state)) }
    imageState = nil
  }

  func abortImage() {
    imageState = nil
    base.abortImage()
  }

  private func decorated(_ event: GraphicsEvent) -> GraphicsEvent {
    GraphicsEvent(
      operation: event.operation,
      before: event.before,
      after: event.after,
      origin: GraphicsEventOrigin(resourceIdentifier: identifier, byteSegments: event.origin?.byteSegments ?? []),
      markedContentPath: [scope] + event.markedContentPath,
      visibility: event.visibility
    )
  }

  private func boundary(
    _ operation: GraphicsMarkedContentOperation,
    state: GraphicsStateSnapshot
  ) -> GraphicsEvent {
    GraphicsEvent(
      operation: .content(.markedContent(operation)),
      before: state,
      after: state,
      origin: .init(resourceIdentifier: identifier)
    )
  }
}
