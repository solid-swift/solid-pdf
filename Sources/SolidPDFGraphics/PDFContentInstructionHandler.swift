protocol PDFContentInstructionHandler: AnyObject {
  func execute(_ instruction: PDFContentInstruction) async throws
  func executeInlineImage(_ image: PDFInlineImage) async throws
  func finish(at location: PDFContentLocation?) async throws
}

extension PDFContentInstructionHandler {
  func executeInlineImage(_ image: PDFInlineImage) async throws {
    throw PDFGraphicsError.unsupported(.operatorName("BI"), location: image.location)
  }
}
