import Foundation
import SolidIO
import Synchronization

final class PDFRC4DecryptionFilter: IncrementalFilter {
  private struct State: Sendable {
    var cipher: PDFRC4
    var finished = false
  }

  private let state: Mutex<State>

  init(key: Data) throws {
    state = Mutex(State(cipher: try PDFRC4(key: key)))
  }

  func process(input: Data) throws -> IncrementalFilterResult {
    state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      return IncrementalFilterResult(
        output: state.cipher.process(input),
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      return Data()
    }
  }
}

final class PDFAESDecryptionFilter: IncrementalFilter {
  private struct State: Sendable {
    let key: Data
    var initializationVector: Data?
    var buffer = Data()
    var finished = false
  }

  private let state: Mutex<State>

  init(key: Data) {
    state = Mutex(State(key: key))
  }

  func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      state.buffer.append(input)
      if state.initializationVector == nil, state.buffer.count >= 16 {
        state.initializationVector = state.buffer.prefix(16)
        state.buffer.removeFirst(16)
      }
      var output = Data()
      while state.initializationVector != nil, state.buffer.count >= 32 {
        let block = Data(state.buffer.prefix(16))
        output.append(
          try PDFCrypto.aesCBCDecrypt(
            block,
            key: state.key,
            initializationVector: state.initializationVector!,
            removesPadding: false
          )
        )
        state.initializationVector = block
        state.buffer.removeFirst(16)
      }
      return IncrementalFilterResult(
        output: output,
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      guard let initializationVector = state.initializationVector,
        state.buffer.count == 16
      else { throw PDFDecryptionError.invalidCiphertext }
      let finalBlock = try PDFCrypto.aesCBCDecrypt(
        state.buffer,
        key: state.key,
        initializationVector: initializationVector,
        removesPadding: false
      )
      guard let padding = finalBlock.last, (1...16).contains(padding) else {
        throw PDFDecryptionError.invalidPadding
      }
      var difference: UInt8 = 0
      for index in 0..<16 {
        let shouldCheck = index >= 16 - Int(padding)
        difference |= shouldCheck ? finalBlock[index] ^ padding : 0
      }
      guard difference == 0 else { throw PDFDecryptionError.invalidPadding }
      return Data(finalBlock.prefix(16 - Int(padding)))
    }
  }
}

final class PDFIdentityDecryptionFilter: IncrementalFilter {
  private let finished = Mutex(false)

  func process(input: Data) throws -> IncrementalFilterResult {
    finished.withLock { finished in
      guard !finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      return IncrementalFilterResult(
        output: input,
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  func finish() throws -> Data? {
    finished.withLock { finished in
      guard !finished else { return nil }
      finished = true
      return Data()
    }
  }
}

private enum PDFDecryptionError: Error {
  case invalidCiphertext
  case invalidPadding
}
