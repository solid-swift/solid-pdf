package protocol PDFRecoveryPass: Sendable {
  var descriptor: PDFRecoveryPassDescriptor { get }
  func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult
}
