import Foundation
import SolidIO

struct PDFStreamFilterSpecification: Sendable {
  let name: PDFName
  let parameters: [PDFName: PDFObject]?
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
    diagnostic: PDFParsingDiagnostic
  ) throws -> any IncrementalFilter {
    switch specification.name {
    case PDFName("FlateDecode"):
      guard specification.parameters == nil else {
        throw PDFParsingError.unsupported(
          .streamFilter(specification.name),
          diagnostic.replacingMessage("Flate predictor parameters are not available yet.")
        )
      }
      return FlateDecoder()
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
}

extension PDFParsingDiagnostic {
  func replacingMessage(_ message: String) -> PDFParsingDiagnostic {
    PDFParsingDiagnostic(offset: offset, object: object, message: message)
  }
}
