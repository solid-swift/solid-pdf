import Crypto
import Foundation

actor PDFEmbeddedFileStreamState: PDFDecodedStreamState {
  private let stream: PDFDecodedStream
  private let declaredSize: Int?
  private let checksum: Data?
  private var hasher = Insecure.MD5()
  private var byteCount = 0
  private var closed = false
  private var validated = false

  init(stream: PDFDecodedStream, declaredSize: Int?, checksum: Data?) {
    self.stream = stream
    self.declaredSize = declaredSize
    self.checksum = checksum
  }

  func next() async throws -> Data? {
    guard !closed else { return nil }
    do {
      if let chunk = try await stream.next() {
        let (nextCount, overflow) = byteCount.addingReportingOverflow(chunk.count)
        guard !overflow else { throw malformed("An embedded file exceeds its supported size.") }
        byteCount = nextCount
        hasher.update(data: chunk)
        return chunk
      }
      try validate()
      await close()
      return nil
    } catch is CancellationError {
      await close()
      throw CancellationError()
    } catch {
      await close()
      throw error
    }
  }

  func close() async {
    guard !closed else { return }
    closed = true
    await stream.close()
  }

  private func validate() throws {
    guard !validated else { return }
    validated = true
    if let declaredSize, declaredSize != byteCount {
      throw malformed("An embedded file does not match its declared Size.")
    }
    if let checksum, !PDFCrypto.constantTimeEqual(Data(hasher.finalize()), checksum) {
      throw malformed("An embedded file does not match its declared CheckSum.")
    }
  }

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }
}
