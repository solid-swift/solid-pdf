import Foundation
import SolidIO

struct PDFStreamCacheKey: Hashable, Sendable {
  let range: PDFSourceRange
  let reference: PDFObjectReference?
  let revision: PDFRevisionIdentifier?
  let security: PDFDocumentSecurity?

  init(_ stream: PDFStreamObject, security: PDFDocumentSecurity?) {
    range = stream.encodedRange
    reference = stream.objectReference
    revision = stream.revision
    self.security = security
  }
}

struct PDFDecodedStreamInput: Sendable {
  let length: Int64
  let read: @Sendable (PDFSourceRange) async throws -> Data
  let close: @Sendable () async -> Void

  init<Session: PDFInputSourceSession>(
    reader: PDFSourceReader<Session>,
    range: PDFSourceRange
  ) {
    length = Int64(range.length)
    read = { relativeRange in
      guard relativeRange.endOffset <= Int64(range.length) else {
        throw PDFParsingError.truncated(
          .init(offset: range.offset + relativeRange.offset, message: "The stream is truncated.")
        )
      }
      return try await reader.read(
        PDFSourceRange(
          uncheckedOffset: range.offset + relativeRange.offset,
          length: relativeRange.length
        )
      )
    }
    close = {}
  }

  init(externalSession session: any PDFInputSourceSession) async throws {
    let length = try await session.length()
    guard length >= 0 else {
      await session.close()
      throw PDFParsingError.sourceFailure(
        .init(offset: 0, message: "The external stream reported an invalid length.")
      )
    }
    self.length = length
    read = { range in
      do {
        return try await session.read(range)
      } catch let error as PDFParsingError {
        throw error
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw PDFParsingError.sourceFailure(
          .init(offset: range.offset, message: "The external stream read failed: \(error)")
        )
      }
    }
    close = { await session.close() }
  }
}

actor PDFDecodedStreamRegistry {
  private var closures = [UUID: @Sendable () async -> Void]()
  private var closed = false

  func register(_ id: UUID, close: @escaping @Sendable () async -> Void) async {
    if closed { await close() } else { closures[id] = close }
  }

  func unregister(_ id: UUID) {
    closures[id] = nil
  }

  func closeAll() async {
    guard !closed else { return }
    closed = true
    let current = closures.values
    closures.removeAll()
    for close in current { await close() }
  }
}

actor PDFBufferedDecodedStreamState: PDFDecodedStreamState {
  private let data: Data
  private let chunkByteCount: Int
  private var offset = 0
  private var closed = false

  init(data: Data, chunkByteCount: Int) {
    self.data = data
    self.chunkByteCount = chunkByteCount
  }

  func next() async throws -> Data? {
    guard !closed else { return nil }
    guard offset < data.count else {
      closed = true
      return nil
    }
    let end = min(data.count, offset + chunkByteCount)
    defer { offset = end }
    return data.subdata(in: offset..<end)
  }

  func close() async { closed = true }
}

actor PDFIncrementalDecodedStreamState: PDFDecodedStreamState {
  private struct Stage {
    let filter: any IncrementalFilter
    var finished = false
  }

  private let id = UUID()
  private let input: PDFDecodedStreamInput
  private let options: PDFParsingOptions
  private let diagnostic: PDFParsingDiagnostic
  private let registry: PDFDecodedStreamRegistry
  private var stages: [Stage]
  private var sourceOffset: Int64 = 0
  private var output = Data()
  private var emittedBytes = 0
  private var finalized = false
  private var closed = false

  init(
    input: PDFDecodedStreamInput,
    filters: [PDFStreamFilterSpecification],
    options: PDFParsingOptions,
    diagnostic: PDFParsingDiagnostic,
    registry: PDFDecodedStreamRegistry
  ) throws {
    guard options.decodedStreamChunkByteCount > 0,
      options.limits.maximumStreamScratchBytes >= options.decodedStreamChunkByteCount,
      options.limits.maximumStreamExpansionRatio > 0
    else {
      throw PDFParsingError.limitExceeded(
        diagnostic.replacingMessage("The stream-decoding limits are invalid.")
      )
    }
    self.input = input
    self.options = options
    self.diagnostic = diagnostic
    self.registry = registry
    stages = try filters.flatMap {
      try PDFStreamFilterFactory.make(
        $0,
        diagnostic: diagnostic,
        maximumDecodedBytes: options.limits.maximumDecodedStreamBytes
      ).map { Stage(filter: $0) }
    }
  }

  func register() async {
    await registry.register(id) { [weak self] in await self?.close() }
  }

  func next() async throws -> Data? {
    guard !closed else { return nil }
    do {
      while output.isEmpty, !finalized {
        try Task.checkCancellation()
        if sourceOffset < input.length, stages.first?.finished != true {
          let count = Int(min(Int64(options.decodedStreamChunkByteCount), input.length - sourceOffset))
          let chunk = try await input.read(
            PDFSourceRange(uncheckedOffset: sourceOffset, length: count)
          )
          guard chunk.count == count else {
            throw PDFParsingError.sourceFailure(
              diagnostic.replacingMessage("The stream source returned a short range.")
            )
          }
          sourceOffset += Int64(count)
          output.append(try process(chunk))
        } else {
          output.append(try finishPipeline())
          finalized = true
        }
        try enforceLimits()
      }
      guard !output.isEmpty else {
        await close()
        return nil
      }
      let count = min(output.count, options.decodedStreamChunkByteCount)
      let chunk = output.prefix(count)
      output.removeFirst(count)
      emittedBytes += count
      return Data(chunk)
    } catch is CancellationError {
      await close()
      throw CancellationError()
    } catch let error as PDFParsingError {
      await close()
      throw error
    } catch {
      await close()
      throw PDFParsingError.malformed(
        diagnostic.replacingMessage("The stream codec rejected its input: \(error)")
      )
    }
  }

  func close() async {
    guard !closed else { return }
    closed = true
    output.removeAll(keepingCapacity: false)
    await input.close()
    await registry.unregister(id)
  }

  private func process(_ source: Data) throws -> Data {
    guard !stages.isEmpty else { return source }
    var current = source
    for index in stages.indices {
      guard !current.isEmpty, !stages[index].finished else {
        current.removeAll(keepingCapacity: false)
        continue
      }
      var produced = Data()
      while !current.isEmpty {
        let result = try stages[index].filter.process(input: current)
        guard result.consumedInput >= 0, result.consumedInput <= current.count else {
          throw PDFParsingError.malformed(
            diagnostic.replacingMessage("A stream codec reported invalid input consumption.")
          )
        }
        produced.append(result.output)
        if result.consumedInput > 0 { current.removeFirst(result.consumedInput) }
        if result.progress == .finished {
          stages[index].finished = true
          break
        }
        guard result.consumedInput > 0 else { break }
      }
      current = produced
    }
    return current
  }

  private func finishPipeline() throws -> Data {
    guard !stages.isEmpty else { return Data() }
    var finalOutput = Data()
    for index in stages.indices {
      var tail = Data()
      if !stages[index].finished {
        tail = try stages[index].filter.finish() ?? Data()
        stages[index].finished = true
      }
      if !tail.isEmpty {
        var current = tail
        if index + 1 < stages.count {
          for downstream in (index + 1)..<stages.count {
            guard !current.isEmpty, !stages[downstream].finished else {
              current.removeAll(keepingCapacity: false)
              break
            }
            let result = try stages[downstream].filter.process(input: current)
            guard result.consumedInput == current.count else {
              throw PDFParsingError.malformed(
                diagnostic.replacingMessage("A stream filter left unexpected intermediate bytes.")
              )
            }
            current = result.output
            if result.progress == .finished { stages[downstream].finished = true }
          }
        }
        finalOutput.append(current)
      }
    }
    return finalOutput
  }

  private func enforceLimits() throws {
    let decoded = emittedBytes + output.count
    guard decoded <= options.limits.maximumDecodedStreamBytes else {
      throw PDFParsingError.limitExceeded(
        diagnostic.replacingMessage("The decoded stream exceeds its configured byte limit.")
      )
    }
    let encodedBytes = Int(min(input.length, Int64(Int.max)))
    let (scaledBytes, multiplicationOverflow) = encodedBytes.multipliedReportingOverflow(
      by: options.limits.maximumStreamExpansionRatio
    )
    let (expandedLimit, additionOverflow) = scaledBytes.addingReportingOverflow(1_024 * 1_024)
    guard !multiplicationOverflow, !additionOverflow, decoded <= expandedLimit else {
      throw PDFParsingError.limitExceeded(
        diagnostic.replacingMessage("The decoded stream exceeds its expansion limit.")
      )
    }
    guard output.count <= options.limits.maximumStreamScratchBytes else {
      throw PDFParsingError.limitExceeded(
        diagnostic.replacingMessage("The stream pipeline exceeds its scratch limit.")
      )
    }
  }
}
