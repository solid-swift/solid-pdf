import Foundation

package enum PDFRecoveryObjectCandidateParser {
  package struct Parsed: Sendable {
    package let boundary: PDFRecoveredObjectBoundary
    package let value: PDFObject
  }

  package static func parse(
    _ candidate: PDFRecoveryIndirectObjectCandidate,
    snapshot: PDFRecoverySnapshot
  ) async throws -> Parsed? {
    let upper = nextBoundary(after: candidate.offset, snapshot: snapshot)
    let distance = upper - candidate.offset
    guard distance > 0,
      distance <= Int64(snapshot.limits.maximumResynchronizationBytes),
      distance <= Int64(Int.max)
    else { return nil }
    let data = try await snapshot.source.read(
      .init(uncheckedOffset: candidate.offset, length: Int(distance))
    )
    let session = try await PDFDataInputSource(data).makeSession()
    var localLimits = snapshot.parsingLimits
    localLimits.maximumInputBytes = Int64(data.count)
    localLimits.maximumCachedSourceBytes = max(localLimits.maximumCachedSourceBytes, min(64 * 1_024, max(1, data.count)))
    let options = PDFParsingOptions(
      limits: localLimits,
      sourceWindowByteCount: min(64 * 1_024, max(1, data.count))
    )
    let reader = try await PDFSourceReader(session: session, options: options)
    do {
      var strict = PDFObjectParser(reader: reader, limits: localLimits)
      if let raw = try? await strict.parseRawIndirectObject(), raw.reference == candidate.reference {
        await reader.close()
        return Parsed(
          boundary: .init(
            reference: candidate.reference,
            sourceRange: shifted(raw.sourceRange, by: candidate.offset),
            streamRange: raw.streamRange.map { shifted($0, by: candidate.offset) },
            hasEndObject: true,
            requiresRecoveredParsing: false,
            repair: nil
          ),
          value: raw.value
        )
      }
      var parser = PDFObjectParser(reader: reader, limits: localLimits)
      let header = try await parser.parseIndirectHeader()
      guard header.reference == candidate.reference else {
        await reader.close()
        return nil
      }
      let value = try await parser.parseObject()
      try await parser.skipWhitespaceAndComments()
      if case .dictionary(let dictionary) = value, try await parser.consumeKeyword("stream") {
        let lineEndingStart = parser.position
        if try await parser.cursor.consume(0x0D) {
          _ = try await parser.cursor.consume(0x0A)
        } else if try await parser.cursor.consume(0x0A) {
          // A single line feed is the complete required separator.
        } else {
          await reader.close()
          return nil
        }
        let streamStart = Int(parser.position)
        guard let recovered = recoverStreamBoundary(
          data: data,
          dictionary: dictionary,
          streamStart: streamStart,
          sourceOffset: candidate.offset,
          policy: snapshot.policy,
          maximumSearchBytes: snapshot.limits.maximumStreamBoundarySearchBytes
        ) else {
          await reader.close()
          return nil
        }
        await reader.close()
        let objectEnd = recovered.endObjectEnd ?? recovered.endStreamEnd
        return Parsed(
          boundary: .init(
            reference: candidate.reference,
            sourceRange: .init(uncheckedOffset: candidate.offset, length: objectEnd),
            streamRange: .init(
              uncheckedOffset: candidate.offset + Int64(streamStart),
              length: recovered.streamEnd - streamStart
            ),
            hasEndObject: recovered.endObjectEnd != nil,
            requiresRecoveredParsing: true,
            repair: .init(
              kind: .streamBoundary,
              classification: recovered.classification,
              sourceRanges: [
                .init(
                  uncheckedOffset: candidate.offset + Int64(lineEndingStart),
                  length: recovered.endStreamEnd - Int(lineEndingStart)
                )
              ],
              message: recovered.message
            )
          ),
          value: value
        )
      }
      let valueEnd = parser.position
      let hasEndObject = try await parser.consumeKeyword("endobj")
      let localEnd = hasEndObject ? parser.position : valueEnd
      guard localEnd > 0, localEnd <= Int64(Int.max) else {
        await reader.close()
        return nil
      }
      await reader.close()
      return Parsed(
        boundary: .init(
          reference: candidate.reference,
          sourceRange: .init(uncheckedOffset: candidate.offset, length: Int(localEnd)),
          streamRange: nil,
          hasEndObject: hasEndObject,
          requiresRecoveredParsing: !hasEndObject,
          repair: hasEndObject ? nil : .init(
            kind: .indirectObject,
            classification: .structuralRepair,
            sourceRanges: [.init(uncheckedOffset: candidate.offset, length: Int(localEnd))],
            message: "The indirect object ended at the next unambiguous structural boundary."
          )
        ),
        value: value
      )
    } catch is CancellationError {
      await reader.close()
      throw CancellationError()
    } catch {
      await reader.close()
      return nil
    }
  }

  package static func parseTrailer(
    at offset: Int64,
    snapshot: PDFRecoverySnapshot
  ) async throws -> [PDFName: PDFObject]? {
    let upper = nextBoundary(after: offset, snapshot: snapshot)
    let distance = upper - offset
    guard distance > 7,
      distance <= Int64(snapshot.limits.maximumResynchronizationBytes),
      distance <= Int64(Int.max)
    else { return nil }
    let data = try await snapshot.source.read(.init(uncheckedOffset: offset, length: Int(distance)))
    let session = try await PDFDataInputSource(data).makeSession()
    var localLimits = snapshot.parsingLimits
    localLimits.maximumInputBytes = Int64(data.count)
    localLimits.maximumCachedSourceBytes = max(localLimits.maximumCachedSourceBytes, min(64 * 1_024, max(1, data.count)))
    let reader = try await PDFSourceReader(
      session: session,
      options: .init(
        limits: localLimits,
        sourceWindowByteCount: min(64 * 1_024, max(1, data.count))
      )
    )
    do {
      var parser = PDFObjectParser(reader: reader, position: 7, limits: localLimits)
      try await parser.skipWhitespaceAndComments()
      guard case .dictionary(let dictionary) = try await parser.parseObject() else {
        await reader.close()
        return nil
      }
      await reader.close()
      return dictionary
    } catch is CancellationError {
      await reader.close()
      throw CancellationError()
    } catch {
      await reader.close()
      return nil
    }
  }

  private static func nextBoundary(
    after offset: Int64,
    snapshot: PDFRecoverySnapshot
  ) -> Int64 {
    let candidates = snapshot.evidence.trailerCandidates
      + snapshot.evidence.classicCrossReferenceCandidates
      + snapshot.evidence.startCrossReferences.map(\.keywordRange.offset)
      + snapshot.evidence.endOfFileCandidates
    return candidates.filter { $0 > offset }.min() ?? snapshot.source.length
  }

  private static func shifted(_ range: PDFSourceRange, by offset: Int64) -> PDFSourceRange {
    .init(uncheckedOffset: range.offset + offset, length: range.length)
  }

  private struct RecoveredStreamBoundary {
    let streamEnd: Int
    let endStreamEnd: Int
    let endObjectEnd: Int?
    let classification: PDFRecoveryClassification
    let message: String
  }

  private static func recoverStreamBoundary(
    data: Data,
    dictionary: [PDFName: PDFObject],
    streamStart: Int,
    sourceOffset: Int64,
    policy: PDFRecoveryPolicy,
    maximumSearchBytes: Int
  ) -> RecoveredStreamBoundary? {
    let searchEnd = min(data.count, streamStart + maximumSearchBytes)
    guard streamStart <= searchEnd else { return nil }
    let marker = Data("endstream".utf8)
    var candidates = [RecoveredStreamBoundary]()
    var search = streamStart..<searchEnd
    while let range = data.range(of: marker, options: [], in: search) {
      let markerStart = range.lowerBound
      let markerEnd = range.upperBound
      if isTokenBoundary(before: markerStart, in: data),
        isTokenBoundary(after: markerEnd, in: data)
      {
        var after = markerEnd
        while after < data.count, isWhitespace(data[after]) { after += 1 }
        let hasEndObject = data[after...].starts(with: Data("endobj".utf8))
        if hasEndObject || after == data.count {
          var streamEnd = markerStart
          if streamEnd > streamStart, data[streamEnd - 1] == 0x0A {
            streamEnd -= 1
            if streamEnd > streamStart, data[streamEnd - 1] == 0x0D { streamEnd -= 1 }
          } else if streamEnd > streamStart, data[streamEnd - 1] == 0x0D {
            streamEnd -= 1
          }
          let declared = dictionary.pdfInteger(named: "Length")
          let matchesDeclared = declared == Int64(streamEnd - streamStart)
          candidates.append(
            .init(
              streamEnd: streamEnd,
              endStreamEnd: markerEnd,
              endObjectEnd: hasEndObject ? after + 6 : nil,
              classification: matchesDeclared ? .byteExact : .structuralRepair,
              message: matchesDeclared
                ? "The stream boundary was confirmed from its declared Length."
                : "The stream boundary was recovered from a validated endstream and endobj pair."
            )
          )
        }
      }
      let next = range.lowerBound + 1
      guard next < searchEnd else { break }
      search = next..<searchEnd
    }
    if let declared = dictionary.pdfInteger(named: "Length"), declared >= 0,
      declared <= Int64(Int.max)
    {
      let expected = streamStart + Int(declared)
      if let exact = candidates.first(where: { $0.streamEnd == expected }) { return exact }
    }
    if candidates.count == 1 { return candidates[0] }
    guard policy == .compatible, let first = candidates.first else { return nil }
    return .init(
      streamEnd: first.streamEnd,
      endStreamEnd: first.endStreamEnd,
      endObjectEnd: first.endObjectEnd,
      classification: .semanticInference,
      message: "Compatibility recovery selected the nearest valid endstream boundary."
    )
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
  }

  private static func isTokenBoundary(before index: Int, in data: Data) -> Bool {
    index == data.startIndex || isWhitespace(data[index - 1]) || isDelimiter(data[index - 1])
  }

  private static func isTokenBoundary(after index: Int, in data: Data) -> Bool {
    index == data.endIndex || isWhitespace(data[index]) || isDelimiter(data[index])
  }

  private static func isDelimiter(_ byte: UInt8) -> Bool {
    [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(byte)
  }
}
