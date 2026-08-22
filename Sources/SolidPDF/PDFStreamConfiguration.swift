import Foundation
import SolidIO
import SolidImageIO

struct PDFStreamFilterSpecification: Sendable {
  let name: PDFName
  let parameters: [PDFName: PDFObject]?
  let implementation: (any IncrementalFilter)?

  init(
    name: PDFName,
    parameters: [PDFName: PDFObject]?,
    implementation: (any IncrementalFilter)? = nil
  ) {
    self.name = name
    self.parameters = parameters
    self.implementation = implementation
  }
}

struct PDFStreamConfiguration: Sendable {
  let fileSpecification: PDFObject?
  let filters: [PDFStreamFilterSpecification]

  static func resolve(
    stream: PDFStreamObject,
    options: PDFParsingOptions,
    resolve: @escaping @Sendable (PDFObjectReference) async throws -> PDFObject
  ) async throws -> PDFStreamConfiguration {
    var references = Set<PDFObjectReference>()
    func resolved(_ value: PDFObject) async throws -> PDFObject {
      switch value {
      case .reference(let reference):
        guard references.insert(reference).inserted else {
          throw PDFParsingError.referenceCycle(Array(references) + [reference])
        }
        defer { references.remove(reference) }
        return try await resolved(resolve(reference))
      case .array(let values):
        var result = [PDFObject]()
        result.reserveCapacity(values.count)
        for value in values { try await result.append(resolved(value)) }
        return .array(result)
      case .dictionary(let dictionary):
        var result = [PDFName: PDFObject]()
        result.reserveCapacity(dictionary.count)
        for (key, value) in dictionary { try await result[key] = resolved(value) }
        return .dictionary(result)
      default:
        return value
      }
    }

    let dictionary = stream.dictionary
    let external = dictionary[PDFName("F")]
    let filterKey = external == nil ? PDFName("Filter") : PDFName("FFilter")
    let canonicalParameters = external == nil
      ? dictionary[PDFName("DecodeParms")]
      : dictionary[PDFName("FDecodeParms")]
    let aliasParameters = external == nil ? dictionary[PDFName("DP")] : nil
    let parameterValue = canonicalParameters
      ?? (options.acceptsStreamFilterAbbreviations ? aliasParameters : nil)
    let filterValue = dictionary[filterKey]

    let resolvedExternal: PDFObject?
    if let external { resolvedExternal = try await resolved(external) } else { resolvedExternal = nil }
    let resolvedFilter: PDFObject?
    if let filterValue {
      resolvedFilter = try await resolved(filterValue)
    } else {
      resolvedFilter = nil
    }
    let resolvedParameters: PDFObject?
    if let parameterValue {
      resolvedParameters = try await resolved(parameterValue)
    } else {
      resolvedParameters = nil
    }
    let names: [PDFName]
    switch resolvedFilter {
    case nil, .null:
      names = []
    case .name(let name):
      names = [try canonicalName(name, options: options, stream: stream)]
    case .array(let values):
      names = try values.map { value in
        guard case .name(let name) = value else {
          throw malformed(stream, "A Filter array contains a non-name value.")
        }
        return try canonicalName(name, options: options, stream: stream)
      }
    default:
      throw malformed(stream, "Filter must be a name or an array of names.")
    }
    guard names.count <= options.limits.maximumStreamFilters else {
      throw PDFParsingError.limitExceeded(
        .init(
          offset: stream.encodedRange.offset,
          object: stream.objectReference,
          message: "The stream filter chain exceeds its configured limit."
        )
      )
    }

    let parameters: [[PDFName: PDFObject]?]
    switch resolvedParameters {
    case nil, .null:
      parameters = Array(repeating: nil, count: names.count)
    case .dictionary(let dictionary):
      guard names.count == 1 else {
        throw malformed(stream, "A DecodeParms dictionary requires exactly one filter.")
      }
      parameters = [dictionary]
    case .array(let values):
      guard values.count == names.count else {
        throw malformed(stream, "Filter and DecodeParms arrays have different lengths.")
      }
      parameters = try values.map { value in
        switch value {
        case .null: nil
        case .dictionary(let dictionary): dictionary
        default: throw malformed(stream, "DecodeParms entries must be dictionaries or null.")
        }
      }
    default:
      throw malformed(stream, "DecodeParms must be a dictionary, array, or null.")
    }
    return PDFStreamConfiguration(
      fileSpecification: resolvedExternal,
      filters: zip(names, parameters).map {
        PDFStreamFilterSpecification(name: $0.0, parameters: $0.1)
      }
    )
  }

  private static func canonicalName(
    _ name: PDFName,
    options: PDFParsingOptions,
    stream: PDFStreamObject
  ) throws -> PDFName {
    let aliases: [PDFName: PDFName] = [
      PDFName("AHx"): PDFName("ASCIIHexDecode"),
      PDFName("A85"): PDFName("ASCII85Decode"),
      PDFName("LZW"): PDFName("LZWDecode"),
      PDFName("Fl"): PDFName("FlateDecode"),
      PDFName("RL"): PDFName("RunLengthDecode"),
      PDFName("CCF"): PDFName("CCITTFaxDecode"),
      PDFName("DCT"): PDFName("DCTDecode"),
    ]
    if let canonical = aliases[name] {
      guard options.acceptsStreamFilterAbbreviations else {
        throw PDFParsingError.unsupported(
          .streamFilter(name),
          .init(
            offset: stream.encodedRange.offset,
            object: stream.objectReference,
            message: "A nonstandard stream-filter abbreviation is disabled in strict mode."
          )
        )
      }
      return canonical
    }
    return name
  }

  private static func malformed(_ stream: PDFStreamObject, _ message: String) -> PDFParsingError {
    .malformed(
      .init(
        offset: stream.encodedRange.offset,
        object: stream.objectReference,
        message: message
      )
    )
  }
}

struct PDFStreamFilterFactory {
  static func make(
    _ specification: PDFStreamFilterSpecification,
    diagnostic: PDFParsingDiagnostic,
    maximumDecodedBytes: Int
  ) throws -> [any IncrementalFilter] {
    if let implementation = specification.implementation { return [implementation] }
    switch specification.name {
    case PDFName("ASCIIHexDecode"):
      return [ASCIIHexDecoder()]
    case PDFName("ASCII85Decode"):
      return [ASCII85Decoder()]
    case PDFName("LZWDecode"):
      let earlyChange = try integer(
        "EarlyChange",
        in: specification.parameters,
        default: 1,
        diagnostic: diagnostic
      )
      guard earlyChange == 0 || earlyChange == 1 else {
        throw malformedParameter("EarlyChange", diagnostic: diagnostic)
      }
      return [
        LZWDecoder(options: try LZWOptions(earlyChange: earlyChange)),
        try predictor(specification.parameters, diagnostic: diagnostic),
      ].compactMap { $0 }
    case PDFName("FlateDecode"):
      return [
        FlateDecoder(),
        try predictor(specification.parameters, diagnostic: diagnostic),
      ].compactMap { $0 }
    case PDFName("RunLengthDecode"):
      return [RunLengthDecoder()]
    case PDFName("CCITTFaxDecode"):
      do {
        return [
          CCITTFaxDecoder(
            options: try CCITTFaxOptions(
              k: try integer("K", in: specification.parameters, default: 0, diagnostic: diagnostic),
              endOfLine: try boolean(
                "EndOfLine",
                in: specification.parameters,
                default: false,
                diagnostic: diagnostic
              ),
              encodedByteAlign: try boolean(
                "EncodedByteAlign",
                in: specification.parameters,
                default: false,
                diagnostic: diagnostic
              ),
              columns: try integer(
                "Columns",
                in: specification.parameters,
                default: 1_728,
                diagnostic: diagnostic
              ),
              rows: try integer("Rows", in: specification.parameters, default: 0, diagnostic: diagnostic),
              endOfBlock: try boolean(
                "EndOfBlock",
                in: specification.parameters,
                default: true,
                diagnostic: diagnostic
              ),
              blackIs1: try boolean(
                "BlackIs1",
                in: specification.parameters,
                default: false,
                diagnostic: diagnostic
              ),
              damagedRowsBeforeError: try integer(
                "DamagedRowsBeforeError",
                in: specification.parameters,
                default: 0,
                diagnostic: diagnostic
              )
            )
          )
        ]
      } catch let error as PDFParsingError {
        throw error
      } catch {
        throw malformedParameter("CCITTFaxDecode", diagnostic: diagnostic)
      }
    case PDFName("DCTDecode"):
      let colorTransform: Int?
      if specification.parameters?[PDFName("ColorTransform")] == nil {
        colorTransform = nil
      } else {
        colorTransform = try integer(
          "ColorTransform",
          in: specification.parameters,
          default: 1,
          diagnostic: diagnostic
        )
      }
      guard colorTransform == nil || colorTransform == 0 || colorTransform == 1 else {
        throw malformedParameter("ColorTransform", diagnostic: diagnostic)
      }
      do {
        return [
          DCTDecoder(
            options: try DCTDecodeOptions(
              colorTransform: colorTransform,
              maximumDecodedBytes: maximumDecodedBytes
            )
          )
        ]
      } catch {
        throw malformedParameter("DCTDecode", diagnostic: diagnostic)
      }
    case PDFName("Crypt"):
      throw PDFParsingError.unsupported(.encryptionFilter, diagnostic)
    case PDFName("JPXDecode"):
      throw PDFParsingError.unsupported(.jpxDecode, diagnostic)
    case PDFName("JBIG2Decode"):
      throw PDFParsingError.unsupported(.jbig2Decode, diagnostic)
    default:
      throw PDFParsingError.unsupported(.streamFilter(specification.name), diagnostic)
    }
  }

  private static func predictor(
    _ parameters: [PDFName: PDFObject]?,
    diagnostic: PDFParsingDiagnostic
  ) throws -> (any IncrementalFilter)? {
    let predictor = try integer("Predictor", in: parameters, default: 1, diagnostic: diagnostic)
    guard predictor == 1 || predictor == 2 || (10...15).contains(predictor) else {
      throw malformedParameter("Predictor", diagnostic: diagnostic)
    }
    guard predictor != 1 else { return nil }
    let colors = try integer("Colors", in: parameters, default: 1, diagnostic: diagnostic)
    let bits = try integer(
      "BitsPerComponent",
      in: parameters,
      default: 8,
      diagnostic: diagnostic
    )
    let columns = try integer("Columns", in: parameters, default: 1, diagnostic: diagnostic)
    do {
      return PredictorDecoder(
        options: try PredictorOptions(
          predictor: predictor,
          colors: colors,
          bitsPerComponent: bits,
          columns: columns
        )
      )
    } catch {
      throw malformedParameter("Predictor", diagnostic: diagnostic)
    }
  }

  private static func integer(
    _ name: PDFName,
    in parameters: [PDFName: PDFObject]?,
    default defaultValue: Int,
    diagnostic: PDFParsingDiagnostic
  ) throws -> Int {
    guard let value = parameters?[name] else { return defaultValue }
    guard case .number(.integer(let integer)) = value,
      integer >= Int64(Int.min), integer <= Int64(Int.max)
    else {
      throw malformedParameter(String(decoding: name.bytes, as: UTF8.self), diagnostic: diagnostic)
    }
    return Int(integer)
  }

  private static func boolean(
    _ name: PDFName,
    in parameters: [PDFName: PDFObject]?,
    default defaultValue: Bool,
    diagnostic: PDFParsingDiagnostic
  ) throws -> Bool {
    guard let value = parameters?[name] else { return defaultValue }
    guard case .boolean(let boolean) = value else {
      throw malformedParameter(String(decoding: name.bytes, as: UTF8.self), diagnostic: diagnostic)
    }
    return boolean
  }

  private static func malformedParameter(
    _ name: String,
    diagnostic: PDFParsingDiagnostic
  ) -> PDFParsingError {
    .malformed(diagnostic.replacingMessage("The \(name) decode parameter is invalid."))
  }
}

extension PDFParsingDiagnostic {
  func replacingMessage(_ message: String) -> PDFParsingDiagnostic {
    PDFParsingDiagnostic(offset: offset, object: object, message: message)
  }
}
