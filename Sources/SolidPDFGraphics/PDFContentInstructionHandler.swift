protocol PDFContentInstructionHandler: AnyObject {
  func execute(_ instruction: PDFContentInstruction) async throws
  func finish(at location: PDFContentLocation?) async throws
}
