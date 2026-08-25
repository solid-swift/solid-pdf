import Foundation

package struct PDFRecoverySource: Sendable {
  package let length: Int64
  private let readRange: @Sendable (PDFSourceRange) async throws -> Data

  init<Session: PDFInputSourceSession>(
    reader: PDFSourceReader<Session>,
    length: Int64
  ) {
    self.length = length
    readRange = { range in try await reader.read(range) }
  }

  package func read(_ range: PDFSourceRange) async throws -> Data {
    try await readRange(range)
  }
}
