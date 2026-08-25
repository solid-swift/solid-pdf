import Foundation

struct PDFCrossReferenceParser<Session: PDFInputSourceSession> {
  let reader: PDFSourceReader<Session>
  let options: PDFParsingOptions
  var overrides: PDFCrossReferenceParsingOverrides? = nil

  func parse() async throws -> PDFCrossReferenceIndex {
    var headerParser = PDFObjectParser(
      reader: reader,
      position: overrides?.headerOffset ?? 0,
      limits: options.limits
    )
    let version = try await headerParser.parseHeader()
    if let overrides, version != overrides.version {
      throw malformed(overrides.headerOffset, "The recovered PDF version changed during validation.")
    }
    let length = try await reader.length()
    let latestOffset: Int64
    if let recovered = overrides?.latestCrossReferenceOffset {
      latestOffset = recovered
    } else {
      latestOffset = try await locateStartCrossReference(length: length)
    }
    var reverseSections = [Section]()
    var seenOffsets = Set<Int64>()
    var offset: Int64? = latestOffset

    while let currentOffset = offset {
      guard reverseSections.count < options.limits.maximumRevisions else {
        throw limit(currentOffset, "The incremental revision count exceeds its configured limit.")
      }
      guard seenOffsets.insert(currentOffset).inserted else {
        throw malformed(currentOffset, "The incremental cross-reference chain contains a cycle.")
      }
      let section = try await parseMainSection(
        at: currentOffset,
        isLatest: reverseSections.isEmpty,
        fileLength: length
      )
      reverseSections.append(section)
      if section.trailer["Prev"] != nil,
        section.trailer.pdfInteger(named: "Prev") == nil
      {
        throw malformed(currentOffset, "The Prev offset must be an integer.")
      }
      if let previous = section.trailer.pdfInteger(named: "Prev") {
        guard previous >= 0, previous < currentOffset else {
          throw malformed(currentOffset, "The Prev offset does not identify an earlier revision.")
        }
        offset = previous
      } else {
        offset = nil
      }
    }

    return try makeIndex(version: version, sections: reverseSections.reversed())
  }

  private func parseMainSection(
    at offset: Int64,
    isLatest: Bool,
    fileLength: Int64
  ) async throws -> Section {
    var parser = PDFObjectParser(reader: reader, position: offset, limits: options.limits)
    var section: Section
    if try await parser.consumeKeyword("xref") {
      section = try await parseClassicSection(using: &parser, at: offset)
      if section.trailer["XRefStm"] != nil,
        section.trailer.pdfInteger(named: "XRefStm") == nil
      {
        throw malformed(offset, "The XRefStm offset must be an integer.")
      }
      if let hybridOffset = section.trailer.pdfInteger(named: "XRefStm") {
        guard hybridOffset >= 0, hybridOffset < offset else {
          throw malformed(offset, "The XRefStm offset is invalid.")
        }
        let hybrid = try await parseStreamSection(at: hybridOffset, readsFooter: false)
        guard hybrid.trailer["Prev"] == nil else {
          throw malformed(hybridOffset, "Prev is not meaningful in a hybrid-reference stream.")
        }
        for (number, entry) in hybrid.entries { section.entries[number] = entry }
        section.representation = .hybrid
      }
      section.endOffset = try await parseFooter(
        using: &parser,
        expectedStartOffset: offset,
        isLatest: isLatest,
        fileLength: fileLength
      )
    } else {
      section = try await parseStreamSection(at: offset, readsFooter: true)
      if isLatest {
        try await validateTrailingWhitespace(from: section.endOffset, fileLength: fileLength)
      }
    }
    return section
  }

  private func makeIndex(
    version: PDFFileVersion,
    sections: some Sequence<Section>
  ) throws -> PDFCrossReferenceIndex {
    let documentIdentifier = UUID()
    var effective = [Int: PDFIndexedCrossReferenceEntry]()
    var revisions = [PDFDocumentRevision]()
    var snapshots = [PDFRevisionIdentifier: [Int: PDFIndexedCrossReferenceEntry]]()
    var initialEncryption: PDFObject?
    var sawInitialEncryption = false

    for (ordinal, section) in sections.enumerated() {
      let revisionIdentifier = PDFRevisionIdentifier(
        documentIdentifier: documentIdentifier,
        ordinal: ordinal
      )
      guard let size = section.trailer.pdfInteger(named: "Size"),
        size > 0,
        size <= Int64(options.limits.maximumObjectCount),
        let root = section.trailer.pdfReference(named: "Root")
      else {
        throw malformed(
          section.startOffset,
          "A cross-reference trailer lacks a valid Size or Root."
        )
      }
      for (number, entry) in section.entries {
        effective[number] = PDFIndexedCrossReferenceEntry(
          entry: entry,
          definitionRevision: revisionIdentifier
        )
      }
      guard effective.keys.allSatisfy({ $0 >= 0 && Int64($0) < size }) else {
        throw malformed(section.startOffset, "An effective cross-reference entry lies outside Size.")
      }
      guard case .free = effective[0]?.entry else {
        throw malformed(section.startOffset, "Cross-reference object zero must be free.")
      }
      try validate(reference: root, in: effective, at: section.startOffset, role: "Root")

      let fileIdentifier = try parseIdentifier(
        section.trailer,
        at: section.startOffset
      )
      let encryption = section.trailer["Encrypt"]
      if !sawInitialEncryption {
        initialEncryption = encryption
        sawInitialEncryption = true
      } else if encryption != initialEncryption {
        throw malformed(
          section.startOffset,
          "Incremental updates cannot introduce, remove, or replace document encryption."
        )
      }
      let revision = PDFDocumentRevision(
        identifier: revisionIdentifier,
        representation: section.representation,
        startCrossReferenceOffset: section.startOffset,
        endOffset: section.endOffset,
        trailer: section.trailer,
        root: root,
        info: section.trailer.pdfReference(named: "Info"),
        fileIdentifier: fileIdentifier,
        encryption: encryption,
        recoveryProvenance: overrides?.recoveryReport.records.isEmpty == false
          ? PDFRecoveryProvenance(
            records: overrides?.recoveryReport.records.map(\.identifier) ?? [],
            classification: overrides?.recoveryReport.records.contains(where: {
              $0.classification == .semanticInference
            }) == true ? .semanticInference : .structuralRepair
          )
          : nil
      )
      revisions.append(revision)
      snapshots[revisionIdentifier] = effective
    }
    guard !revisions.isEmpty else { throw malformed(0, "The document has no revisions.") }
    return PDFCrossReferenceIndex(
      version: version,
      revisions: revisions,
      snapshots: snapshots,
      recoveryReport: overrides?.recoveryReport,
      recoveredObjectBoundaries: [:],
      recoveredValueOverrides: [:]
    )
  }

  private func validate(
    reference: PDFObjectReference,
    in entries: [Int: PDFIndexedCrossReferenceEntry],
    at offset: Int64,
    role: String
  ) throws {
    guard let indexed = entries[reference.objectNumber] else {
      throw malformed(offset, "The trailer \(role) is absent from the cross-reference index.")
    }
    switch indexed.entry {
    case .uncompressed(_, let generation):
      guard generation == reference.generationNumber else {
        throw malformed(offset, "The trailer \(role) generation does not match its entry.")
      }
    case .compressed:
      guard reference.generationNumber == 0 else {
        throw malformed(offset, "A compressed trailer \(role) must use generation zero.")
      }
    case .free:
      throw malformed(offset, "The trailer \(role) refers to a free object.")
    }
  }

  private func parseIdentifier(
    _ trailer: [PDFName: PDFObject],
    at offset: Int64
  ) throws -> [PDFString]? {
    guard let values = trailer.pdfArray(named: "ID") else { return nil }
    let strings = values.compactMap { value -> PDFString? in
      guard case .string(let string) = value else { return nil }
      return string
    }
    guard strings.count == values.count, strings.count == 2 else {
      throw malformed(offset, "The trailer ID must contain two strings.")
    }
    return strings
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
    guard tail[eof.upperBound...].allSatisfy(PDFObjectParser<Session>.isWhitespace) else {
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
    using parser: inout PDFObjectParser<Session>,
    at startOffset: Int64
  ) async throws -> Section {
    var entries = [Int: PDFCrossReferenceEntry]()
    while true {
      try await parser.skipWhitespaceAndComments()
      if try await parser.consumeKeyword("trailer") {
        try await parser.skipWhitespaceAndComments()
        guard case .dictionary(let trailer) = try await parser.parseObject() else {
          throw malformed(parser.position, "The trailer value must be a dictionary.")
        }
        return Section(
          entries: entries,
          trailer: trailer,
          representation: .classic,
          startOffset: startOffset,
          endOffset: parser.position
        )
      }
      let subsectionOffset = parser.position
      let first = try await parser.parseUnsignedIntegerToken()
      try await parser.skipWhitespaceAndComments()
      let count = try await parser.parseUnsignedIntegerToken()
      guard first <= Int64(Int.max), count >= 0, count <= Int64(Int.max),
        first <= Int64(options.limits.maximumObjectCount) - count
      else { throw limit(subsectionOffset, "The cross-reference subsection exceeds limits.") }
      try await consumeLineEnding(using: &parser)
      for relative in 0..<Int(count) {
        let lineOffset = parser.position
        let line = try await readLine(using: &parser)
        let fields = line.split(separator: 0x20, omittingEmptySubsequences: true)
        guard fields.count == 3, fields[0].count == 10, fields[1].count == 5,
          fields[2].count == 1, let offset = Self.decimal(fields[0]),
          let generation = Self.decimal(fields[1]), generation <= 65_535
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
          guard offset < (try await reader.length()) else {
            throw malformed(lineOffset, "An in-use object offset lies outside the file.")
          }
          entries[number] = .uncompressed(offset: offset, generationNumber: Int(generation))
        default:
          throw malformed(lineOffset, "The cross-reference entry status is invalid.")
        }
      }
    }
  }

  private func parseStreamSection(at offset: Int64, readsFooter: Bool) async throws -> Section {
    var parser = PDFObjectParser(reader: reader, position: offset, limits: options.limits)
    let indirect = try await parser.parseRawIndirectObject()
    guard case .dictionary(let dictionary) = indirect.value,
      dictionary.pdfName(named: "Type") == PDFName("XRef"),
      let range = indirect.streamRange,
      let size = dictionary.pdfInteger(named: "Size"), size > 0,
      size <= Int64(options.limits.maximumObjectCount)
    else { throw malformed(offset, "The object at startxref is not a valid cross-reference stream.") }
    let encoded = try await reader.read(range)
    let decoded = try await PDFStructuralStreamDecoder.decode(
      encoded,
      dictionary: dictionary,
      limits: options.limits,
      offset: range.offset
    )
    let widths = try integerArray(dictionary, name: "W", expectedCount: 3, offset: offset)
    guard widths.allSatisfy({ (0...8).contains($0) }) else {
      throw malformed(offset, "Cross-reference field widths must be between zero and eight.")
    }
    let indexes = try crossReferenceIndexes(dictionary, size: Int(size), offset: offset)
    let entryWidth = try PDFCheckedArithmetic.add(
      try PDFCheckedArithmetic.add(widths[0], widths[1], offset: offset),
      widths[2],
      offset: offset
    )
    guard entryWidth > 0 else { throw malformed(offset, "The cross-reference entry width is zero.") }
    var entryCount = 0
    for pair in stride(from: 0, to: indexes.count, by: 2) {
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
        entries[objectNumber] = try await crossReferenceEntry(
          type: type,
          field2: field2,
          field3: field3,
          offset: offset
        )
      }
    }
    let endOffset = readsFooter
      ? try await parseFooter(
        using: &parser,
        expectedStartOffset: offset,
        isLatest: false,
        fileLength: try await reader.length()
      )
      : parser.position
    return Section(
      entries: entries,
      trailer: dictionary,
      representation: .stream,
      startOffset: offset,
      endOffset: endOffset
    )
  }

  private func crossReferenceIndexes(
    _ dictionary: [PDFName: PDFObject],
    size: Int,
    offset: Int64
  ) throws -> [Int] {
    let indexes = dictionary["Index"] == nil
      ? [0, size]
      : try integerArray(dictionary, name: "Index", expectedCount: nil, offset: offset)
    guard indexes.count.isMultiple(of: 2) else {
      throw malformed(offset, "The cross-reference Index must contain pairs.")
    }
    var previousEnd = 0
    for pair in stride(from: 0, to: indexes.count, by: 2) {
      let first = indexes[pair]
      let count = indexes[pair + 1]
      guard first >= previousEnd, first <= size, count >= 0, count <= size - first else {
        throw malformed(offset, "The cross-reference Index is unsorted or outside Size.")
      }
      previousEnd = first + count
    }
    return indexes
  }

  private func crossReferenceEntry(
    type: UInt64,
    field2: UInt64,
    field3: UInt64,
    offset: Int64
  ) async throws -> PDFCrossReferenceEntry {
    switch type {
    case 0:
      guard field2 <= UInt64(Int.max), field3 <= 65_535 else {
        throw malformed(offset, "A free cross-reference entry exceeds supported ranges.")
      }
      return .free(nextObjectNumber: Int(field2), generationNumber: Int(field3))
    case 1:
      guard field2 <= UInt64(Int64.max), field3 <= 65_535,
        Int64(field2) < (try await reader.length())
      else { throw malformed(offset, "An in-use cross-reference entry is invalid.") }
      return .uncompressed(offset: Int64(field2), generationNumber: Int(field3))
    case 2:
      guard field2 > 0, field2 <= UInt64(Int.max), field3 <= UInt64(Int.max) else {
        throw malformed(offset, "A compressed cross-reference entry is invalid.")
      }
      return .compressed(objectStreamNumber: Int(field2), index: Int(field3))
    default:
      throw malformed(offset, "The cross-reference entry type is unsupported.")
    }
  }

  private func parseFooter(
    using parser: inout PDFObjectParser<Session>,
    expectedStartOffset: Int64,
    isLatest: Bool,
    fileLength: Int64
  ) async throws -> Int64 {
    try await parser.skipWhitespaceAndComments()
    try await parser.requireKeyword("startxref")
    try await requireWhitespace(using: &parser)
    let value = try await parser.parseUnsignedIntegerToken()
    guard value == expectedStartOffset || overrides?.acceptsMismatchedFooter == true else {
      throw malformed(parser.position, "A revision footer does not identify its cross-reference section.")
    }
    try await requireWhitespace(using: &parser)
    let hasEndOfFile: Bool
    if overrides?.acceptsMissingEndOfFile == true,
      fileLength - parser.position < Int64("%%EOF".utf8.count)
    {
      hasEndOfFile = false
    } else {
      hasEndOfFile = try await parser.cursor.consume(Array("%%EOF".utf8))
    }
    guard hasEndOfFile || overrides?.acceptsMissingEndOfFile == true else {
      throw malformed(parser.position, "A revision is missing its %%EOF marker.")
    }
    let endOffset = hasEndOfFile ? parser.position : min(parser.position, fileLength)
    if isLatest { try await validateTrailingWhitespace(from: endOffset, fileLength: fileLength) }
    return endOffset
  }

  private func validateTrailingWhitespace(from offset: Int64, fileLength: Int64) async throws {
    guard offset <= fileLength else { throw malformed(offset, "The revision end lies outside the file.") }
    let count = fileLength - offset
    guard count <= Int64(Int.max) else { throw limit(offset, "The trailing byte count is too large.") }
    let trailing = try await reader.read(
      PDFSourceRange(uncheckedOffset: offset, length: Int(count))
    )
    guard trailing.allSatisfy(PDFObjectParser<Session>.isWhitespace) else {
      throw malformed(offset, "Non-whitespace follows the terminal %%EOF marker.")
    }
  }

  private func requireWhitespace(using parser: inout PDFObjectParser<Session>) async throws {
    guard let first = try await parser.cursor.peekByte(), PDFObjectParser<Session>.isWhitespace(first)
    else { throw malformed(parser.position, "A revision footer requires whitespace.") }
    while let byte = try await parser.cursor.peekByte(), PDFObjectParser<Session>.isWhitespace(byte) {
      _ = try await parser.cursor.readByte()
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
      guard case .number(.integer(let integer)) = value, integer >= 0,
        integer <= Int64(Int.max)
      else { throw malformed(offset, "A cross-reference array value is invalid.") }
      return Int(integer)
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
    var entries: [Int: PDFCrossReferenceEntry]
    let trailer: [PDFName: PDFObject]
    var representation: PDFCrossReferenceRepresentation
    let startOffset: Int64
    var endOffset: Int64
  }
}
