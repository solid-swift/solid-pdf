import SolidPDF
import SolidPostScript

extension PDFGraphicsInstructionHandler {
  func paintAnnotationAppearance(
    _ stream: PDFStreamObject,
    annotation: PDFAnnotation,
    page: PDFPage,
    resourceFallbackAllowed: Bool
  ) async throws {
    guard let reference = stream.objectReference else {
      throw annotationError("An annotation appearance must have indirect identity.", annotation: annotation, page: page)
    }
    if !resourceFallbackAllowed, stream.dictionary["Resources"] == nil {
      throw annotationError("A PDF 2.0 annotation appearance requires its own Resources.", annotation: annotation, page: page)
    }
    let values = try PDFObjectAccess.numbers(stream.dictionary["BBox"] ?? .null)
    guard values.count == 4 else {
      throw annotationError("An annotation appearance requires a valid BBox.", annotation: annotation, page: page)
    }
    let bounds = GraphicsRect(
      x: min(values[0], values[2]),
      y: min(values[1], values[3]),
      width: abs(values[2] - values[0]),
      height: abs(values[3] - values[1])
    )
    guard bounds.width > 0, bounds.height > 0 else {
      throw annotationError("An annotation appearance BBox must have positive area.", annotation: annotation, page: page)
    }
    let rect = annotation.rectangle
    let placement = GraphicsMatrix(
      a: (rect.maximumX - rect.minimumX) / bounds.width,
      b: 0,
      c: 0,
      d: (rect.maximumY - rect.minimumY) / bounds.height,
      tx: rect.minimumX - bounds.x * (rect.maximumX - rect.minimumX) / bounds.width,
      ty: rect.minimumY - bounds.y * (rect.maximumY - rect.minimumY) / bounds.height
    )
    let saved = state
    state.matrix = placement.concatenated(with: state.matrix)
    let location = PDFContentLocation(
      revision: resources.revision,
      pageIndex: page.index,
      pageReference: page.reference,
      decodedOffset: 0,
      segments: [],
      resourceStack: [reference]
    )
    do {
      try await paintForm(
        stream,
        reference: reference,
        instruction: PDFContentInstruction(operands: [], name: "annotation-appearance", location: location)
      )
      state = saved
    } catch {
      state = saved
      throw error
    }
  }

  private func annotationError(
    _ message: String,
    annotation: PDFAnnotation,
    page: PDFPage
  ) -> PDFGraphicsError {
    .malformedContent(
      message: message,
      operatorName: "annotation-appearance",
      location: .init(
        revision: resources.revision,
        pageIndex: page.index,
        pageReference: page.reference,
        decodedOffset: 0,
        segments: []
      )
    )
  }
}
