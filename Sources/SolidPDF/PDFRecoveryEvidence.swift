import Foundation

package struct PDFRecoveryStartCrossReference: Sendable, Hashable {
  package let keywordRange: PDFSourceRange
  package let valueRange: PDFSourceRange
  package let value: Int64
}

package struct PDFRecoveryIndirectObjectCandidate: Sendable, Hashable {
  package let reference: PDFObjectReference
  package let offset: Int64
}

package struct PDFRecoveryEvidence: Sendable {
  package let headerCandidates: [Int64]
  package let endOfFileCandidates: [Int64]
  package let startCrossReferences: [PDFRecoveryStartCrossReference]
  package let classicCrossReferenceCandidates: [Int64]
  package let indirectObjectCandidates: [PDFRecoveryIndirectObjectCandidate]
  package let trailerCandidates: [Int64]

  package static func collect(
    from source: PDFRecoverySource,
    limits: PDFRecoveryLimits
  ) async throws -> Self {
    guard limits.maximumScanBytes >= 0,
      source.length <= limits.maximumScanBytes,
      limits.maximumScratchBytes >= 256,
      limits.maximumCandidateRevisions > 0
    else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "The recovery scan exceeds its configured limits.")
      )
    }
    let chunkSize = min(64 * 1_024, limits.maximumScratchBytes)
    let overlap = 128
    var headers = Set<Int64>()
    var ends = Set<Int64>()
    var starts = [Int64: PDFRecoveryStartCrossReference]()
    var crossReferences = Set<Int64>()
    var indirectObjects = Set<PDFRecoveryIndirectObjectCandidate>()
    var trailers = Set<Int64>()
    var offset: Int64 = 0
    var carry = Data()
    while offset < source.length {
      try Task.checkCancellation()
      let length = Int(min(Int64(chunkSize), source.length - offset))
      let chunk = try await source.read(.init(uncheckedOffset: offset, length: length))
      var data = carry
      data.append(chunk)
      let base = offset - Int64(carry.count)
      scan(
        data,
        base: base,
        sourceLength: source.length,
        headers: &headers,
        ends: &ends,
        starts: &starts,
        crossReferences: &crossReferences,
        indirectObjects: &indirectObjects,
        trailers: &trailers
      )
      carry = Data(data.suffix(min(overlap, data.count)))
      offset += Int64(length)
    }
    guard starts.count <= limits.maximumCandidateRevisions,
      ends.count <= limits.maximumCandidateRevisions,
      crossReferences.count <= limits.maximumCandidateRevisions,
      indirectObjects.count <= limits.maximumCandidateObjects
    else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "The recovery framing candidates exceed their limit.")
      )
    }
    return Self(
      headerCandidates: headers.sorted(),
      endOfFileCandidates: ends.sorted(),
      startCrossReferences: starts.values.sorted { $0.keywordRange.offset < $1.keywordRange.offset },
      classicCrossReferenceCandidates: crossReferences.sorted()
      ,
      indirectObjectCandidates: indirectObjects.sorted { $0.offset < $1.offset },
      trailerCandidates: trailers.sorted()
    )
  }

  private static func scan(
    _ data: Data,
    base: Int64,
    sourceLength: Int64,
    headers: inout Set<Int64>,
    ends: inout Set<Int64>,
    starts: inout [Int64: PDFRecoveryStartCrossReference],
    crossReferences: inout Set<Int64>,
    indirectObjects: inout Set<PDFRecoveryIndirectObjectCandidate>,
    trailers: inout Set<Int64>
  ) {
    find(Data("%PDF-".utf8), in: data).forEach { index in
      let absolute = base + Int64(index)
      if (0..<1_024).contains(absolute) { headers.insert(absolute) }
    }
    find(Data("%%EOF".utf8), in: data).forEach { index in
      let absolute = base + Int64(index)
      if absolute >= 0, absolute < sourceLength { ends.insert(absolute) }
    }
    find(Data("xref".utf8), in: data).forEach { index in
      let absolute = base + Int64(index)
      guard absolute >= 0, absolute < sourceLength,
        isTokenBoundary(before: index, in: data),
        isTokenBoundary(after: index + 4, in: data)
      else { return }
      crossReferences.insert(absolute)
    }
    find(Data("startxref".utf8), in: data).forEach { index in
      let absolute = base + Int64(index)
      guard absolute >= 0, absolute < sourceLength else { return }
      var valueStart = index + 9
      while valueStart < data.count, PDFObjectParser<PDFDataInputSource.Session>.isWhitespace(data[valueStart]) {
        valueStart += 1
      }
      var valueEnd = valueStart
      var value: Int64 = 0
      while valueEnd < data.count, (0x30...0x39).contains(data[valueEnd]) {
        let (scaled, overflow1) = value.multipliedReportingOverflow(by: 10)
        let (next, overflow2) = scaled.addingReportingOverflow(Int64(data[valueEnd] - 0x30))
        guard !overflow1, !overflow2 else { return }
        value = next
        valueEnd += 1
      }
      guard valueEnd > valueStart else { return }
      let keyword = PDFSourceRange(uncheckedOffset: absolute, length: 9)
      let valueRange = PDFSourceRange(
        uncheckedOffset: base + Int64(valueStart),
        length: valueEnd - valueStart
      )
      starts[absolute] = .init(keywordRange: keyword, valueRange: valueRange, value: value)
    }
    find(Data("trailer".utf8), in: data).forEach { index in
      let absolute = base + Int64(index)
      guard absolute >= 0, absolute < sourceLength,
        isTokenBoundary(before: index, in: data),
        isTokenBoundary(after: index + 7, in: data)
      else { return }
      trailers.insert(absolute)
    }
    scanIndirectObjectHeaders(
      data,
      base: base,
      sourceLength: sourceLength,
      into: &indirectObjects
    )
  }

  private static func scanIndirectObjectHeaders(
    _ data: Data,
    base: Int64,
    sourceLength: Int64,
    into candidates: inout Set<PDFRecoveryIndirectObjectCandidate>
  ) {
    var index = data.startIndex
    while index < data.endIndex {
      guard (0x31...0x39).contains(data[index]), isTokenBoundary(before: index, in: data) else {
        index += 1
        continue
      }
      let start = index
      guard let objectNumber = decimal(in: data, index: &index), objectNumber <= Int64(Int.max),
        consumeWhitespace(in: data, index: &index),
        let generation = decimal(in: data, index: &index), generation <= 65_535,
        consumeWhitespace(in: data, index: &index),
        data[index...].starts(with: Data("obj".utf8)),
        isTokenBoundary(after: index + 3, in: data)
      else {
        index = start + 1
        continue
      }
      let absolute = base + Int64(start)
      if absolute >= 0, absolute < sourceLength {
        candidates.insert(
          .init(
            reference: .init(
              uncheckedObjectNumber: Int(objectNumber),
              generationNumber: Int(generation)
            ),
            offset: absolute
          )
        )
      }
      index += 3
    }
  }

  private static func decimal(in data: Data, index: inout Int) -> Int64? {
    let start = index
    var value: Int64 = 0
    while index < data.endIndex, (0x30...0x39).contains(data[index]) {
      let (scaled, overflow1) = value.multipliedReportingOverflow(by: 10)
      let (next, overflow2) = scaled.addingReportingOverflow(Int64(data[index] - 0x30))
      guard !overflow1, !overflow2 else { return nil }
      value = next
      index += 1
    }
    return index > start ? value : nil
  }

  private static func consumeWhitespace(in data: Data, index: inout Int) -> Bool {
    let start = index
    while index < data.endIndex, PDFObjectParser<PDFDataInputSource.Session>.isWhitespace(data[index]) {
      index += 1
    }
    return index > start
  }

  private static func find(_ pattern: Data, in data: Data) -> [Int] {
    guard !pattern.isEmpty, data.count >= pattern.count else { return [] }
    var result = [Int]()
    var search = data.startIndex..<data.endIndex
    while let range = data.range(of: pattern, options: [], in: search) {
      result.append(range.lowerBound)
      let next = range.lowerBound + 1
      guard next < data.endIndex else { break }
      search = next..<data.endIndex
    }
    return result
  }

  private static func isTokenBoundary(before index: Int, in data: Data) -> Bool {
    index == data.startIndex || isDelimiter(data[index - 1])
  }

  private static func isTokenBoundary(after index: Int, in data: Data) -> Bool {
    index == data.endIndex || isDelimiter(data[index])
  }

  private static func isDelimiter(_ byte: UInt8) -> Bool {
    PDFObjectParser<PDFDataInputSource.Session>.isWhitespace(byte)
      || [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(byte)
  }
}
