import SolidPDF

protocol PDFContentInstructionHandler: AnyObject {
  func execute(_ instruction: PDFContentInstruction) async throws
  func inlineImageByteCount(
    dictionary: [PDFName: PDFObject],
    location: PDFContentLocation
  ) async throws -> Int
  func executeInlineImage(_ image: PDFInlineImage) async throws
  func finish(at location: PDFContentLocation?) async throws
}

extension PDFContentInstructionHandler {
  func inlineImageByteCount(
    dictionary _: [PDFName: PDFObject],
    location: PDFContentLocation
  ) async throws -> Int {
    throw PDFGraphicsError.unsupported(.operatorName("BI"), location: location)
  }

  func executeInlineImage(_ image: PDFInlineImage) async throws {
    throw PDFGraphicsError.unsupported(.operatorName("BI"), location: image.location)
  }
}
