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
            hasEndObject: true
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
      if case .dictionary = value, try await parser.consumeKeyword("stream") {
        await reader.close()
        return nil
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
          hasEndObject: hasEndObject
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
    let candidates = snapshot.evidence.indirectObjectCandidates.map(\.offset)
      + snapshot.evidence.trailerCandidates
      + snapshot.evidence.classicCrossReferenceCandidates
      + snapshot.evidence.startCrossReferences.map(\.keywordRange.offset)
      + snapshot.evidence.endOfFileCandidates
    return candidates.filter { $0 > offset }.min() ?? snapshot.source.length
  }

  private static func shifted(_ range: PDFSourceRange, by offset: Int64) -> PDFSourceRange {
    .init(uncheckedOffset: range.offset + offset, length: range.length)
  }
}
