package struct PDFCrossReferenceReconstructionPass: PDFRecoveryPass {
  package let descriptor = PDFRecoveryPassDescriptor(
    identifier: "xref.reconstruct-index",
    stage: .crossReferenceDiscovery,
    priority: 100,
    invalidates: [.objectBoundaries, .streamBoundaries, .documentStructure, .finalValidation]
  )

  package init() {}

  package func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    guard snapshot.model.crossReferenceFailure != nil,
      !snapshot.model.contains(fact: "reconstructed-xref"),
      let version = snapshot.model.version,
      let endOffset = snapshot.model.endOffset
    else { return .noMatch }
    var parsedByNumber = [Int: [PDFRecoveryObjectCandidateParser.Parsed]]()
    for candidate in snapshot.evidence.indirectObjectCandidates {
      try Task.checkCancellation()
      if let parsed = try await PDFRecoveryObjectCandidateParser.parse(candidate, snapshot: snapshot) {
        parsedByNumber[candidate.reference.objectNumber, default: []].append(parsed)
      }
    }
    let provenStreamRanges = parsedByNumber.values
      .flatMap { $0 }
      .compactMap(\.boundary.streamRange)
    parsedByNumber = parsedByNumber.compactMapValues { candidates in
      let filtered = candidates.filter { parsed in
        !provenStreamRanges.contains { range in
          range.offset <= parsed.boundary.sourceRange.offset
            && parsed.boundary.sourceRange.offset < range.endOffset
        }
      }
      return filtered.isEmpty ? nil : filtered
    }
    guard !parsedByNumber.isEmpty else {
      return .unrecoverable(.init(offset: 0, message: "Recovery found no complete indirect objects."))
    }
    var selected = [Int: PDFRecoveryObjectCandidateParser.Parsed]()
    var inferredDuplicate = false
    for (number, candidates) in parsedByNumber {
      if candidates.count == 1 {
        selected[number] = candidates[0]
      } else if snapshot.policy == .compatible {
        selected[number] = candidates.max { lhs, rhs in
          lhs.boundary.sourceRange.offset < rhs.boundary.sourceRange.offset
        }
        inferredDuplicate = true
      } else {
        return .unrecoverable(
          .init(offset: candidates[0].boundary.sourceRange.offset, message: "Multiple definitions of object \(number) are ambiguous without cross-reference evidence.")
        )
      }
    }
    var trailers = [(Int64, [PDFName: PDFObject])]()
    for offset in snapshot.evidence.trailerCandidates {
      if let dictionary = try await PDFRecoveryObjectCandidateParser.parseTrailer(
        at: offset,
        snapshot: snapshot
      ) {
        trailers.append((offset, dictionary))
      }
    }
    guard let chosenTrailer = trailers.last else {
      return .unrecoverable(.init(offset: 0, message: "Recovery found no valid trailer dictionary."))
    }
    if trailers.count > 1, snapshot.policy == .structural {
      return .unrecoverable(
        .init(offset: chosenTrailer.0, message: "Multiple trailer dictionaries require compatible recovery.")
      )
    }
    var trailer = chosenTrailer.1
    let maximumObject = selected.keys.max() ?? 0
    let size = maximumObject + 1
    trailer["Size"] = .integer(size)
    var entries: [Int: PDFCrossReferenceEntry] = [
      0: .free(nextObjectNumber: 0, generationNumber: 65_535)
    ]
    var boundaries = [Int: PDFRecoveredObjectBoundary]()
    for (number, parsed) in selected {
      entries[number] = .uncompressed(
        offset: parsed.boundary.sourceRange.offset,
        generationNumber: parsed.boundary.reference.generationNumber
      )
      boundaries[number] = parsed.boundary
    }
    let classification: PDFRecoveryClassification = inferredDuplicate || trailers.count > 1
      ? .semanticInference
      : .structuralRepair
    let plan = PDFRecoveredCrossReferencePlan(
      version: version,
      representation: .classic,
      entries: entries,
      trailer: trailer,
      boundaries: boundaries,
      valueOverrides: [:],
      startOffset: snapshot.model.startCrossReferenceOffset ?? chosenTrailer.0,
      endOffset: endOffset
    )
    return .proposals([
      .init(
        fact: "reconstructed-xref",
        kind: .crossReference,
        classification: classification,
        sourceRanges: [.init(uncheckedOffset: chosenTrailer.0, length: 7)],
        message: classification == .semanticInference
          ? "Compatibility recovery reconstructed an effective index from the latest object and trailer candidates."
          : "Recovery reconstructed an unambiguous effective index from object and trailer candidates.",
        mutation: .reconstructedCrossReference(plan)
      )
    ])
  }
}
