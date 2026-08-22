import Foundation
import SolidIO

struct PDFCrossReferenceParser<Session: PDFInputSourceSession> {
  let reader: PDFSourceReader<Session>
  let options: PDFParsingOptions

  func parse() async throws -> PDFCrossReferenceIndex {
    var headerParser = PDFObjectParser(reader: reader, limits: options.limits)
    let version = try await headerParser.parseHeader()
    let length = try await reader.length()
    let startOffset = try await locateStartCrossReference(length: length)
    var parser = PDFObjectParser(
      reader: reader,
      position: startOffset,
      limits: options.limits
    )
    let section: Section
    if try await parser.consumeKeyword("xref") {
      section = try await parseClassicSection(using: &parser)
    } else {
      section = try await parseStreamSection(at: startOffset)
    }
    var entries = section.entries
    if let hybridOffset = section.trailer.pdfInteger(named: "XRefStm") {
      guard hybridOffset >= 0 else {
        throw malformed(hybridOffset, "The XRefStm offset is invalid.")
      }
      let hybrid = try await parseStreamSection(at: hybridOffset)
      for (number, entry) in hybrid.entries { entries[number] = entry }
      try rejectEarlierRevision(in: hybrid.trailer, at: hybridOffset)
    }
    try rejectEarlierRevision(in: section.trailer, at: startOffset)
    if section.trailer["Encrypt"] != nil {
      throw PDFParsingError.unsupported(
        .encryption,
        .init(offset: startOffset, message: "Encrypted PDF documents are not yet supported.")
      )
    }
    guard let size = section.trailer.pdfInteger(named: "Size"),
      size > 0,
      size <= Int64(options.limits.maximumObjectCount),
      let root = section.trailer.pdfReference(named: "Root")
    else {
      throw malformed(startOffset, "The cross-reference trailer lacks a valid Size or Root.")
    }
    guard entries.keys.allSatisfy({ $0 >= 0 && Int64($0) < size }) else {
      throw malformed(startOffset, "A cross-reference entry lies outside the declared Size.")
    }
    guard case .free = entries[0] else {
      throw malformed(startOffset, "Cross-reference object zero must be a free entry.")
    }
    guard let rootEntry = entries[root.objectNumber] else {
      throw malformed(startOffset, "The trailer Root is absent from the cross-reference index.")
    }
    switch rootEntry {
    case .uncompressed(_, let generation):
      guard generation == root.generationNumber else {
        throw malformed(startOffset, "The trailer Root generation does not match its index entry.")
      }
    case .compressed:
      guard root.generationNumber == 0 else {
        throw malformed(startOffset, "A compressed Root must use generation zero.")
      }
    case .free:
      throw malformed(startOffset, "The trailer Root refers to a free object.")
    }
    let identifier: [PDFString]?
    if let values = section.trailer.pdfArray(named: "ID") {
      let strings = values.compactMap { value -> PDFString? in
        guard case .string(let string) = value else { return nil }
        return string
      }
      guard strings.count == values.count, strings.count == 2 else {
        throw malformed(startOffset, "The trailer ID must contain two strings.")
      }
      identifier = strings
    } else {
      identifier = nil
    }
    return PDFCrossReferenceIndex(
      version: version,
      entries: entries,
      trailer: section.trailer,
      startCrossReferenceOffset: startOffset,
      root: root,
      info: section.trailer.pdfReference(named: "Info"),
      identifier: identifier
    )
  }

  private func locateStartCrossReference(length: Int64) async throws -> Int64 {
    let searchLength = Int(min(length, Int64(options.limits.maximumTailSearchBytes)))
    let searchOffset = length - Int64(searchLength)
    let tail = try await reader.read(
      PDFSourceRange(uncheckedOffset: searchOffset, length: searchLength)
    )
    let eofMarker = Data("%%EOF".utf8)
    guard let eof = tail.range(of: eofMarker, options: .backwards) else {
      throw malformed(searchOffset, "The terminal %%EOF marker is missing.")
    }
    let trailing = tail[eof.upperBound...]
    guard trailing.allSatisfy(PDFObjectParser<Session>.isWhitespace) else {
      throw malformed(searchOffset + Int64(eof.upperBound), "Non-whitespace follows %%EOF.")
    }
    let prefix = tail[..<eof.lowerBound]
    let marker = Data("startxref".utf8)
    guard let start = prefix.range(of: marker, options: .backwards) else {
      throw malformed(searchOffset, "The terminal startxref entry is missing.")
    }
    var index = start.upperBound
    while index < prefix.endIndex, PDFObjectParser<Session>.isWhitespace(prefix[index]) {
      index = prefix.index(after: index)
    }
    var value: Int64 = 0
    var digits = 0
    while index < prefix.endIndex, (0x30...0x39).contains(prefix[index]) {
      let digit = Int64(prefix[index] - 0x30)
      let (scaled, overflow1) = value.multipliedReportingOverflow(by: 10)
      let (next, overflow2) = scaled.addingReportingOverflow(digit)
      guard !overflow1, !overflow2 else {
        throw limit(searchOffset + Int64(index), "The startxref offset overflowed.")
      }
      value = next
      digits += 1
      index = prefix.index(after: index)
    }
    guard digits > 0, value < length else {
      throw malformed(searchOffset + Int64(start.lowerBound), "The startxref offset is invalid.")
    }
    return value
  }

  private func parseClassicSection(
    using parser: inout PDFObjectParser<Session>
  ) async throws -> Section {
    var entries = [Int: PDFCrossReferenceEntry]()
    while true {
      try await parser.skipWhitespaceAndComments()
      if try await parser.consumeKeyword("trailer") {
        try await parser.skipWhitespaceAndComments()
        guard case .dictionary(let trailer) = try await parser.parseObject() else {
          throw malformed(parser.position, "The trailer value must be a dictionary.")
        }
        return Section(entries: entries, trailer: trailer)
      }
      let subsectionOffset = parser.position
      let first = try await parser.parseUnsignedIntegerToken()
      try await parser.skipWhitespaceAndComments()
      let count = try await parser.parseUnsignedIntegerToken()
      guard first <= Int64(Int.max), count <= Int64(Int.max),
        count >= 0,
        first + count <= Int64(options.limits.maximumObjectCount)
      else { throw limit(subsectionOffset, "The cross-reference subsection exceeds limits.") }
      try await consumeLineEnding(using: &parser)
      for relative in 0..<Int(count) {
        let lineOffset = parser.position
        let line = try await readLine(using: &parser)
        let fields = line.split(separator: 0x20, omittingEmptySubsequences: true)
        guard fields.count == 3,
          fields[0].count == 10,
          fields[1].count == 5,
          fields[2].count == 1,
          let offset = Self.decimal(fields[0]),
          let generation = Self.decimal(fields[1]),
          generation <= 65_535
        else { throw malformed(lineOffset, "A classic cross-reference entry is malformed.") }
        let number = Int(first) + relative
        guard entries[number] == nil else {
          throw malformed(lineOffset, "A cross-reference subsection overlaps an earlier entry.")
        }
        switch fields[2][fields[2].startIndex] {
        case 0x66:
          guard offset <= Int64(Int.max) else {
            throw malformed(lineOffset, "A free-list object number is too large.")
          }
          entries[number] = .free(
            nextObjectNumber: Int(offset),
            generationNumber: Int(generation)
          )
        case 0x6E:
          let length = try await reader.length()
          guard offset < length else {
            throw malformed(lineOffset, "An in-use object offset lies outside the file.")
          }
          entries[number] = .uncompressed(
            offset: offset,
            generationNumber: Int(generation)
          )
        default:
          throw malformed(lineOffset, "The cross-reference entry status is invalid.")
        }
      }
    }
  }

  private func parseStreamSection(at offset: Int64) async throws -> Section {
    var parser = PDFObjectParser(reader: reader, position: offset, limits: options.limits)
    let indirect = try await parser.parseRawIndirectObject()
    guard case .dictionary(let dictionary) = indirect.value,
      dictionary.pdfName(named: "Type") == PDFName("XRef"),
      let range = indirect.streamRange,
      let size = dictionary.pdfInteger(named: "Size"),
      size > 0,
      size <= Int64(options.limits.maximumObjectCount)
    else { throw malformed(offset, "The object at startxref is not a valid cross-reference stream.") }
    let encoded = try await reader.read(range)
    let decoded = try decodeStructuralStream(encoded, dictionary: dictionary, offset: range.offset)
    let widths = try integerArray(dictionary, name: "W", expectedCount: 3, offset: offset)
    guard widths.allSatisfy({ (0...8).contains($0) }) else {
      throw malformed(offset, "Cross-reference field widths must be between zero and eight.")
    }
    let indexes: [Int]
    if dictionary["Index"] == nil {
      indexes = [0, Int(size)]
    } else {
      indexes = try integerArray(dictionary, name: "Index", expectedCount: nil, offset: offset)
      guard indexes.count.isMultiple(of: 2) else {
        throw malformed(offset, "The cross-reference Index must contain pairs.")
      }
    }
    let entryWidth = try PDFCheckedArithmetic.add(
      try PDFCheckedArithmetic.add(widths[0], widths[1], offset: offset),
      widths[2],
      offset: offset
    )
    guard entryWidth > 0 else { throw malformed(offset, "The cross-reference entry width is zero.") }
    var entryCount = 0
    for pair in stride(from: 0, to: indexes.count, by: 2) {
      guard indexes[pair] >= 0, indexes[pair + 1] >= 0,
        indexes[pair] <= Int(size),
        indexes[pair + 1] <= Int(size) - indexes[pair]
      else { throw malformed(offset, "The cross-reference Index lies outside Size.") }
      entryCount = try PDFCheckedArithmetic.add(entryCount, indexes[pair + 1], offset: offset)
    }
    let expectedBytes = try PDFCheckedArithmetic.multiply(entryCount, entryWidth, offset: offset)
    guard decoded.count == expectedBytes else {
      throw malformed(range.offset, "The cross-reference stream byte count does not match W and Index.")
    }
    var span = PDFParserSpan(decoded)
    var entries = [Int: PDFCrossReferenceEntry]()
    for pair in stride(from: 0, to: indexes.count, by: 2) {
      for relative in 0..<indexes[pair + 1] {
        let objectNumber = indexes[pair] + relative
        let type = widths[0] == 0 ? 1 : try span.readBigEndianInteger(byteCount: widths[0])
        let field2 = try span.readBigEndianInteger(byteCount: widths[1])
        let field3 = try span.readBigEndianInteger(byteCount: widths[2])
        guard entries[objectNumber] == nil else {
          throw malformed(offset, "The cross-reference stream Index overlaps itself.")
        }
        switch type {
        case 0:
          guard field2 <= UInt64(Int.max), field3 <= 65_535 else {
            throw malformed(offset, "A free cross-reference entry exceeds supported ranges.")
          }
          entries[objectNumber] = .free(
            nextObjectNumber: Int(field2),
            generationNumber: Int(field3)
          )
        case 1:
          guard field2 <= UInt64(Int64.max), field3 <= 65_535,
            Int64(field2) < (try await reader.length())
          else { throw malformed(offset, "An in-use cross-reference entry is invalid.") }
          entries[objectNumber] = .uncompressed(
            offset: Int64(field2),
            generationNumber: Int(field3)
          )
        case 2:
          guard field2 > 0, field2 <= UInt64(Int.max), field3 <= UInt64(Int.max) else {
            throw malformed(offset, "A compressed cross-reference entry is invalid.")
          }
          entries[objectNumber] = .compressed(
            objectStreamNumber: Int(field2),
            index: Int(field3)
          )
        default:
          throw malformed(offset, "The cross-reference entry type is unsupported.")
        }
      }
    }
    return Section(entries: entries, trailer: dictionary)
  }

  private func decodeStructuralStream(
    _ data: Data,
    dictionary: [PDFName: PDFObject],
    offset: Int64
  ) throws -> Data {
    if dictionary["Filter"] == nil { return data }
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
      guard result.progress == .finished, result.consumedInput == data.count,
        result.output.count <= options.limits.maximumDecodedStreamBytes
      else { throw malformed(offset, "The Flate structural stream is truncated or oversized.") }
      return result.output
    } catch let error as PDFParsingError {
      throw error
    } catch {
      throw malformed(offset, "The Flate structural stream is malformed: \(error)")
    }
  }

  private func integerArray(
    _ dictionary: [PDFName: PDFObject],
    name: PDFName,
    expectedCount: Int?,
    offset: Int64
  ) throws -> [Int] {
    guard let values = dictionary.pdfArray(named: name),
      expectedCount == nil || values.count == expectedCount
    else { throw malformed(offset, "The \(String(decoding: name.bytes, as: UTF8.self)) array is invalid.") }
    return try values.map { value in
      guard case .number(.integer(let integer)) = value, integer >= 0, integer <= Int64(Int.max)
      else { throw malformed(offset, "A cross-reference array value is invalid.") }
      return Int(integer)
    }
  }

  private func rejectEarlierRevision(
    in trailer: [PDFName: PDFObject],
    at offset: Int64
  ) throws {
    guard trailer["Prev"] == nil else {
      throw PDFParsingError.unsupported(
        .incrementalUpdates,
        .init(offset: offset, message: "Incrementally updated PDFs are not yet supported.")
      )
    }
  }

  private func consumeLineEnding(using parser: inout PDFObjectParser<Session>) async throws {
    while try await parser.cursor.consume(0x20) {}
    if try await parser.cursor.consume(0x0D) {
      _ = try await parser.cursor.consume(0x0A)
      return
    }
    guard try await parser.cursor.consume(0x0A) else {
      throw malformed(parser.position, "A cross-reference line ending is required.")
    }
  }

  private func readLine(using parser: inout PDFObjectParser<Session>) async throws -> Data {
    let start = parser.position
    var data = Data()
    while let byte = try await parser.cursor.peekByte(), byte != 0x0A, byte != 0x0D {
      data.append(try await parser.cursor.readByte())
      guard data.count <= 32 else {
        throw malformed(start, "A classic cross-reference entry is too long.")
      }
    }
    try await consumeLineEnding(using: &parser)
    return data
  }

  private func malformed(_ offset: Int64, _ message: String) -> PDFParsingError {
    .malformed(.init(offset: max(0, offset), message: message))
  }

  private func limit(_ offset: Int64, _ message: String) -> PDFParsingError {
    .limitExceeded(.init(offset: max(0, offset), message: message))
  }

  private static func decimal(_ bytes: Data.SubSequence) -> Int64? {
    var value: Int64 = 0
    for byte in bytes {
      guard (0x30...0x39).contains(byte) else { return nil }
      let (scaled, overflow1) = value.multipliedReportingOverflow(by: 10)
      let (next, overflow2) = scaled.addingReportingOverflow(Int64(byte - 0x30))
      guard !overflow1, !overflow2 else { return nil }
      value = next
    }
    return value
  }

  private struct Section {
    let entries: [Int: PDFCrossReferenceEntry]
    let trailer: [PDFName: PDFObject]
  }
}
