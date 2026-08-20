import Foundation
import SolidPostScript

/// An immutable parsed PostScript or Encapsulated PostScript document.
public struct PostScriptDocument: Sendable {
  private enum Source: Sendable, Equatable { case data, stagedStandardInput }

  public let data: Data
  public let metadata: PostScriptDocumentMetadata
  private let source: Source

  /// Parses an in-memory document.
  public init(data: Data, options: PostScriptDocumentParsingOptions = .init()) throws {
    let parsed = try PostScriptDocumentParser.parse(data, options: options)
    self.data = data
    self.metadata = parsed
    self.source = .data
  }

  /// Reads and parses a file URL.
  public init(contentsOf url: URL, options: PostScriptDocumentParsingOptions = .init()) throws {
    try self.init(data: Data(contentsOf: url, options: [.mappedIfSafe]), options: options)
  }

  /// Parses bytes staged from standard input while retaining `%stdin` execution identity.
  public static func stagedStandardInput(
    _ data: Data,
    options: PostScriptDocumentParsingOptions = .init()
  ) throws -> PostScriptDocument {
    let parsed = try PostScriptDocumentParser.parse(data, options: options)
    return PostScriptDocument(data: data, metadata: parsed, source: .stagedStandardInput)
  }

  /// Returns the exact executable program bytes selected from the container.
  public var programData: Data {
    data.subdata(in: metadata.programByteRange)
  }

  var usesStagedStandardInput: Bool { source == .stagedStandardInput }

  private init(data: Data, metadata: PostScriptDocumentMetadata, source: Source) {
    self.data = data
    self.metadata = metadata
    self.source = source
  }
}

private enum PostScriptDocumentParser {
  private struct Line {
    let range: Range<Int>
    let content: String
  }

  static func parse(
    _ input: Data,
    options: PostScriptDocumentParsingOptions
  ) throws -> PostScriptDocumentMetadata {
    guard input.count <= options.limits.maximumInputBytes else { throw PostScriptDocumentError.inputTooLarge }
    let programRange = try programRange(in: input)
    let data = input.subdata(in: programRange)
    let firstLine = try nextLine(in: data, from: 0, limit: options.limits.maximumLineBytes)?.content ?? ""
    let claimsDSC = firstLine.hasPrefix("%!PS-Adobe-")
    let identifiesEPS = claimsDSC && firstLine.contains("EPSF-")
    let extensionKind = options.assumedKind
    let kind: PostScriptDocumentKind = identifiesEPS || extensionKind == .encapsulatedPostScript
      ? .encapsulatedPostScript : .postScript

    if options.strict, kind == .encapsulatedPostScript, !identifiesEPS {
      throw PostScriptDocumentError.missingEPSHeader
    }

    var title: String?
    var creator: String?
    var version: String?
    var boundingBox: PostScriptDocumentBounds?
    var highResolutionBox: PostScriptDocumentBounds?
    var boundingBoxAtEnd = false
    var highResolutionBoxAtEnd = false
    var declaredPages: Int?
    var pagesAtEnd = false
    var pages: [PostScriptDocumentPage] = []
    var currentPageIndex: Int?
    var nesting = 0
    var warnings: [String] = []
    var offset = 0

    while let line = try nextLine(in: data, from: offset, limit: options.limits.maximumLineBytes) {
      offset = line.range.upperBound
      let text = line.content
      if text.hasPrefix("%%BeginDocument") {
        nesting += 1
        guard nesting <= options.limits.maximumNestingDepth else {
          throw PostScriptDocumentError.nestingLimit(offset: programRange.lowerBound + line.range.lowerBound)
        }
        continue
      }
      if text.hasPrefix("%%EndDocument") {
        if nesting == 0 {
          try diagnose("Unmatched %%EndDocument", line: line, programRange: programRange, options: options, warnings: &warnings)
        } else {
          nesting -= 1
        }
        continue
      }
      guard nesting == 0 else { continue }

      if text.hasPrefix("%%BeginBinary:") {
        let count = try dataCount(after: "%%BeginBinary:", in: text, line: line, programRange: programRange)
        guard count <= data.count - offset else {
          throw PostScriptDocumentError.truncatedData(offset: programRange.lowerBound + offset)
        }
        offset += count
        continue
      }
      if text.hasPrefix("%%BeginData:") {
        let fields = fields(after: "%%BeginData:", in: text)
        guard let count = fields.first.flatMap(Int.init), count >= 0 else {
          try diagnose("Invalid %%BeginData count", line: line, programRange: programRange, options: options, warnings: &warnings)
          continue
        }
        if fields.dropFirst().contains(where: { $0.caseInsensitiveCompare("Lines") == .orderedSame }) {
          for _ in 0..<count {
            guard let skipped = try nextLine(in: data, from: offset, limit: options.limits.maximumLineBytes) else {
              throw PostScriptDocumentError.truncatedData(offset: programRange.lowerBound + offset)
            }
            offset = skipped.range.upperBound
          }
        } else {
          guard count <= data.count - offset else {
            throw PostScriptDocumentError.truncatedData(offset: programRange.lowerBound + offset)
          }
          offset += count
        }
        continue
      }

      switch true {
      case text.hasPrefix("%%Title:"):
        title = value(after: "%%Title:", in: text)
      case text.hasPrefix("%%Creator:"):
        creator = value(after: "%%Creator:", in: text)
      case text.hasPrefix("%%Version:"):
        version = value(after: "%%Version:", in: text)
      case text.hasPrefix("%%HiResBoundingBox:"):
        let value = value(after: "%%HiResBoundingBox:", in: text)
        if value == "(atend)" { highResolutionBoxAtEnd = true } else {
          highResolutionBox = try parseBounds(value, line: line, programRange: programRange, options: options, warnings: &warnings)
        }
      case text.hasPrefix("%%BoundingBox:"):
        let value = value(after: "%%BoundingBox:", in: text)
        if value == "(atend)" { boundingBoxAtEnd = true } else {
          boundingBox = try parseBounds(value, line: line, programRange: programRange, options: options, warnings: &warnings)
        }
      case text.hasPrefix("%%Pages:"):
        let value = value(after: "%%Pages:", in: text)
        if value == "(atend)" { pagesAtEnd = true } else if let count = Int(value.split(whereSeparator: \.isWhitespace).first ?? ""), count >= 0 {
          declaredPages = count
        } else {
          try diagnose("Invalid %%Pages", line: line, programRange: programRange, options: options, warnings: &warnings)
        }
      case text.hasPrefix("%%Page:"):
        guard pages.count < options.limits.maximumPages else { throw PostScriptDocumentError.inputTooLarge }
        if let previous = currentPageIndex {
          let page = pages[previous]
          pages[previous] = .init(label: page.label, ordinal: page.ordinal, bounds: page.bounds,
            byteRange: page.byteRange.map { $0.lowerBound..<programRange.lowerBound + line.range.lowerBound })
        }
        let parts = fields(after: "%%Page:", in: text)
        let ordinal = parts.last.flatMap(Int.init) ?? pages.count + 1
        pages.append(.init(label: parts.first ?? String(ordinal), ordinal: ordinal, bounds: nil,
          byteRange: (programRange.lowerBound + line.range.lowerBound)..<programRange.upperBound))
        currentPageIndex = pages.count - 1
      case text.hasPrefix("%%PageBoundingBox:"):
        if let currentPageIndex {
          let page = pages[currentPageIndex]
          let bounds = try parseBounds(value(after: "%%PageBoundingBox:", in: text), line: line,
            programRange: programRange, options: options, warnings: &warnings)
          pages[currentPageIndex] = .init(label: page.label, ordinal: page.ordinal, bounds: bounds, byteRange: page.byteRange)
        }
      default:
        break
      }
    }

    if nesting != 0 {
      try diagnose("Unclosed %%BeginDocument", line: Line(range: data.count..<data.count, content: ""),
        programRange: programRange, options: options, warnings: &warnings)
    }
    if let currentPageIndex {
      let page = pages[currentPageIndex]
      pages[currentPageIndex] = .init(label: page.label, ordinal: page.ordinal, bounds: page.bounds,
        byteRange: page.byteRange.map { $0.lowerBound..<programRange.upperBound })
    }
    if (boundingBoxAtEnd || highResolutionBoxAtEnd) && boundingBox == nil && highResolutionBox == nil {
      try diagnose("Unresolved bounding box declared (atend)", line: Line(range: data.count..<data.count, content: ""),
        programRange: programRange, options: options, warnings: &warnings)
    }
    if pagesAtEnd, declaredPages == nil { declaredPages = pages.count }
    let resolvedBounds = highResolutionBox ?? boundingBox
    if kind == .encapsulatedPostScript, resolvedBounds == nil, options.strict {
      throw PostScriptDocumentError.missingEPSBoundingBox
    }
    if claimsDSC, options.strict, !firstLine.hasPrefix("%!PS-Adobe-") {
      throw PostScriptDocumentError.malformedDSC(offset: programRange.lowerBound, message: "Invalid DSC header")
    }
    return PostScriptDocumentMetadata(
      kind: kind, title: title, creator: creator, version: version, bounds: resolvedBounds,
      pages: pages, declaredPageCount: declaredPages, warnings: warnings, programByteRange: programRange
    )
  }

  private static func programRange(in data: Data) throws -> Range<Int> {
    guard data.count >= 4 else { return 0..<data.count }
    let bytes = [UInt8](data.prefix(12))
    guard bytes.prefix(4) == [0xC5, 0xD0, 0xD3, 0xC6] else { return 0..<data.count }
    guard data.count >= 12 else { throw PostScriptDocumentError.truncatedData(offset: 0) }
    let offset = littleEndianUInt32(bytes[4..<8])
    let length = littleEndianUInt32(bytes[8..<12])
    guard let offset = Int(exactly: offset), let length = Int(exactly: length), offset <= data.count,
      length <= data.count - offset
    else { throw PostScriptDocumentError.truncatedData(offset: 4) }
    return offset..<(offset + length)
  }

  private static func littleEndianUInt32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
    bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
  }

  private static func nextLine(in data: Data, from start: Int, limit: Int) throws -> Line? {
    guard start < data.count else { return nil }
    var index = start
    while index < data.count, data[index] != 0x0A, data[index] != 0x0D {
      index += 1
      guard index - start <= limit else { throw PostScriptDocumentError.lineTooLong(offset: start) }
    }
    let content = String(data: data[start..<index], encoding: .isoLatin1) ?? ""
    if index < data.count {
      let first = data[index]
      index += 1
      if first == 0x0D, index < data.count, data[index] == 0x0A { index += 1 }
    }
    return Line(range: start..<index, content: content)
  }

  private static func parseBounds(
    _ value: String,
    line: Line,
    programRange: Range<Int>,
    options: PostScriptDocumentParsingOptions,
    warnings: inout [String]
  ) throws -> PostScriptDocumentBounds? {
    let numbers = value.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
    guard numbers.count == 4 else {
      try diagnose("Invalid bounding box", line: line, programRange: programRange, options: options, warnings: &warnings)
      return nil
    }
    do { return try .init(lowerX: numbers[0], lowerY: numbers[1], upperX: numbers[2], upperY: numbers[3]) }
    catch {
      try diagnose("Invalid bounding box", line: line, programRange: programRange, options: options, warnings: &warnings)
      return nil
    }
  }

  private static func diagnose(
    _ message: String,
    line: Line,
    programRange: Range<Int>,
    options: PostScriptDocumentParsingOptions,
    warnings: inout [String]
  ) throws {
    let offset = programRange.lowerBound + line.range.lowerBound
    if options.strict { throw PostScriptDocumentError.malformedDSC(offset: offset, message: message) }
    warnings.append("byte \(offset): \(message)")
  }

  private static func value(after prefix: String, in text: String) -> String {
    String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
  }

  private static func fields(after prefix: String, in text: String) -> [String] {
    value(after: prefix, in: text).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func dataCount(after prefix: String, in text: String, line: Line, programRange: Range<Int>) throws -> Int {
    guard let first = fields(after: prefix, in: text).first, let count = Int(first), count >= 0 else {
      throw PostScriptDocumentError.malformedDSC(
        offset: programRange.lowerBound + line.range.lowerBound,
        message: "Invalid binary byte count"
      )
    }
    return count
  }
}
