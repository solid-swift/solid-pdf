import Foundation
import SolidIO

enum PDFStructuralStreamDecoder {
  static func decode(
    _ data: Data,
    dictionary: [PDFName: PDFObject],
    limits: PDFParsingLimits,
    offset: Int64
  ) throws -> Data {
    if dictionary["Filter"] == nil {
      guard data.count <= limits.maximumDecodedStreamBytes else {
        throw PDFParsingError.limitExceeded(
          .init(offset: offset, message: "The structural stream exceeds its decoded-size limit.")
        )
      }
      return data
    }
    let filter: PDFName?
    switch dictionary["Filter"] {
    case .name(let name):
      filter = name
    case .array(let values) where values.count == 1:
      if case .name(let name) = values[0] { filter = name } else { filter = nil }
    default:
      filter = nil
    }
    guard filter == PDFName("FlateDecode"),
      dictionary["DecodeParms"] == nil || dictionary["DecodeParms"] == .null
    else {
      throw PDFParsingError.unsupported(
        .structuralStreamFilter,
        .init(offset: offset, message: "Only raw or plain Flate structural streams are supported.")
      )
    }
    do {
      let decoder = FlateDecoder()
      let result = try decoder.process(input: data)
      guard result.progress == .finished, result.consumedInput == data.count else {
        throw malformed(offset, "The Flate structural stream is truncated.")
      }
      guard result.output.count <= limits.maximumDecodedStreamBytes else {
        throw PDFParsingError.limitExceeded(
          .init(offset: offset, message: "The decoded structural stream exceeds its limit.")
        )
      }
      return result.output
    } catch let error as PDFParsingError {
      throw error
    } catch {
      throw malformed(offset, "The Flate structural stream is malformed: \(error)")
    }
  }

  private static func malformed(_ offset: Int64, _ message: String) -> PDFParsingError {
    .malformed(.init(offset: offset, message: message))
  }
}
