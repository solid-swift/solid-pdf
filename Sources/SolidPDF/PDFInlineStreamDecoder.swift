import Foundation
import SolidIO

package final class PDFInlineStreamDecoder {
  package struct Result: Sendable {
    package let output: Data
    package let finished: Bool
  }

  private struct Stage {
    let filter: any IncrementalFilter
    var finished = false
    var pending = Data()
  }

  private var stages: [Stage]
  private var sourceFinished = false
  private var finalized = false
  private let diagnostic: PDFParsingDiagnostic
  private let maximumBufferedBytes: Int
  private var producedBytes = 0

  package init(
    dictionary: [PDFName: PDFObject],
    maximumFilters: Int,
    maximumDecodedBytes: Int,
    diagnostic: PDFParsingDiagnostic
  ) throws {
    self.diagnostic = diagnostic
    maximumBufferedBytes = maximumDecodedBytes
    let specifications = try Self.specifications(
      dictionary: dictionary,
      maximumFilters: maximumFilters,
      diagnostic: diagnostic
    )
    stages = try specifications.flatMap {
      try PDFStreamFilterFactory.make(
        $0,
        diagnostic: diagnostic,
        maximumDecodedBytes: maximumDecodedBytes
      ).map { Stage(filter: $0) }
    }
    guard !stages.isEmpty else {
      throw PDFParsingError.malformed(diagnostic.replacingMessage("A filtered inline image has no filters."))
    }
  }

  package func process(_ input: Data) throws -> Result {
    guard !sourceFinished, !finalized else {
      return Result(output: Data(), finished: true)
    }
    try appendPending(input, to: 0)
    var current = try drainStages()
    sourceFinished = stages[0].finished
    guard sourceFinished else {
      try account(current.count)
      return Result(output: current, finished: false)
    }
    current.append(try finishPipeline())
    finalized = true
    try account(current.count)
    return Result(output: current, finished: true)
  }

  private func finishPipeline() throws -> Data {
    var finalOutput = Data()
    for index in stages.indices {
      finalOutput.append(try drainStage(index))
      if !stages[index].finished {
        let filter = stages[index].filter
        let tail = try filter.finish() ?? Data()
        stages[index].finished = true
        try append(tail, after: index, finalOutput: &finalOutput)
      }
    }
    finalOutput.append(try drainStages())
    return finalOutput
  }

  private func drainStages() throws -> Data {
    var output = Data()
    for index in stages.indices { output.append(try drainStage(index)) }
    return output
  }

  private func drainStage(_ index: Int) throws -> Data {
    var output = Data()
    guard !stages[index].finished else {
      guard stages[index].pending.isEmpty else {
        throw PDFParsingError.malformed(
          diagnostic.replacingMessage("An inline-image filter left trailing intermediate bytes.")
        )
      }
      return output
    }
    while !stages[index].pending.isEmpty {
      let filter = stages[index].filter
      let pending = Data(stages[index].pending)
      let result = try filter.process(input: pending)
      guard result.consumedInput >= 0, result.consumedInput <= stages[index].pending.count else {
        throw PDFParsingError.malformed(
          diagnostic.replacingMessage("An inline-image filter reported invalid input consumption.")
        )
      }
      if result.consumedInput > 0 { stages[index].pending.removeFirst(result.consumedInput) }
      try append(result.output, after: index, finalOutput: &output)
      if result.progress == .finished {
        stages[index].finished = true
        guard stages[index].pending.isEmpty else {
          throw PDFParsingError.malformed(
            diagnostic.replacingMessage("An inline-image filter consumed bytes beyond its end marker.")
          )
        }
        break
      }
      guard result.consumedInput > 0 else { break }
    }
    return output
  }

  private func append(_ data: Data, after index: Int, finalOutput: inout Data) throws {
    guard !data.isEmpty else { return }
    if index + 1 < stages.count {
      guard !stages[index + 1].finished else {
        throw PDFParsingError.malformed(
          diagnostic.replacingMessage("An inline-image filter produced data after its successor ended.")
        )
      }
      try appendPending(data, to: index + 1)
    } else {
      finalOutput.append(data)
    }
  }

  private func appendPending(_ data: Data, to index: Int) throws {
    var total = data.count
    for stage in stages {
      let next = total.addingReportingOverflow(stage.pending.count)
      guard !next.overflow else {
        throw PDFParsingError.limitExceeded(
          diagnostic.replacingMessage("Inline-image filter scratch exceeds its limit.")
        )
      }
      total = next.partialValue
    }
    guard total <= maximumBufferedBytes else {
      throw PDFParsingError.limitExceeded(
        diagnostic.replacingMessage("Inline-image filter scratch exceeds its limit.")
      )
    }
    stages[index].pending.append(data)
  }

  private func account(_ count: Int) throws {
    let total = producedBytes.addingReportingOverflow(count)
    guard !total.overflow, total.partialValue <= maximumBufferedBytes else {
      throw PDFParsingError.limitExceeded(
        diagnostic.replacingMessage("Decoded inline-image data exceeds its limit.")
      )
    }
    producedBytes = total.partialValue
  }

  private static func specifications(
    dictionary: [PDFName: PDFObject],
    maximumFilters: Int,
    diagnostic: PDFParsingDiagnostic
  ) throws -> [PDFStreamFilterSpecification] {
    let filterObject = dictionary["Filter"] ?? dictionary["F"]
    let parameterObject = dictionary["DecodeParms"] ?? dictionary["DP"]
    let names: [PDFName]
    switch filterObject {
    case .name(let name): names = [try canonicalInlineName(name, diagnostic: diagnostic)]
    case .array(let values):
      names = try values.map {
        guard case .name(let name) = $0 else {
          throw PDFParsingError.malformed(diagnostic.replacingMessage("An inline Filter array contains a non-name."))
        }
        return try canonicalInlineName(name, diagnostic: diagnostic)
      }
    case nil, .null: names = []
    default:
      throw PDFParsingError.malformed(diagnostic.replacingMessage("Inline Filter must be a name or name array."))
    }
    guard names.count <= maximumFilters else {
      throw PDFParsingError.limitExceeded(diagnostic.replacingMessage("The inline filter chain exceeds its limit."))
    }
    let parameters: [[PDFName: PDFObject]?]
    switch parameterObject {
    case nil, .null: parameters = Array(repeating: nil, count: names.count)
    case .dictionary(let value):
      guard names.count == 1 else {
        throw PDFParsingError.malformed(
          diagnostic.replacingMessage("An inline DecodeParms dictionary requires one filter.")
        )
      }
      parameters = [value]
    case .array(let values):
      guard values.count == names.count else {
        throw PDFParsingError.malformed(
          diagnostic.replacingMessage("Inline Filter and DecodeParms arrays have different lengths.")
        )
      }
      parameters = try values.map {
        switch $0 {
        case .null: nil
        case .dictionary(let value): value
        default:
          throw PDFParsingError.malformed(
            diagnostic.replacingMessage("Inline DecodeParms entries must be dictionaries or null.")
          )
        }
      }
    default:
      throw PDFParsingError.malformed(
        diagnostic.replacingMessage("Inline DecodeParms must be a dictionary, array, or null.")
      )
    }
    return zip(names, parameters).map {
      PDFStreamFilterSpecification(name: $0.0, parameters: $0.1)
    }
  }

  private static func canonicalInlineName(
    _ name: PDFName,
    diagnostic: PDFParsingDiagnostic
  ) throws -> PDFName {
    let aliases: [PDFName: PDFName] = [
      "AHx": "ASCIIHexDecode",
      "A85": "ASCII85Decode",
      "LZW": "LZWDecode",
      "Fl": "FlateDecode",
      "RL": "RunLengthDecode",
      "CCF": "CCITTFaxDecode",
      "DCT": "DCTDecode",
    ]
    let canonical = aliases[name] ?? name
    switch canonical {
    case "ASCIIHexDecode", "ASCII85Decode", "LZWDecode", "FlateDecode", "RunLengthDecode",
      "CCITTFaxDecode", "DCTDecode":
      return canonical
    case "Crypt", "JPXDecode", "JBIG2Decode":
      throw PDFParsingError.unsupported(
        canonical == "Crypt" ? .encryptionFilter : canonical == "JPXDecode" ? .jpxDecode : .jbig2Decode,
        diagnostic
      )
    default:
      throw PDFParsingError.unsupported(.streamFilter(canonical), diagnostic)
    }
  }
}
