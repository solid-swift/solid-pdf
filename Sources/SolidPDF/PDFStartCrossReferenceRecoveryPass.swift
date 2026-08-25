package struct PDFStartCrossReferenceRecoveryPass: PDFRecoveryPass {
  package let descriptor = PDFRecoveryPassDescriptor(
    identifier: "xref.terminal-offset",
    stage: .crossReferenceDiscovery,
    invalidates: [.objectBoundaries, .streamBoundaries, .documentStructure, .finalValidation]
  )

  package init() {}

  package func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    guard !snapshot.model.contains(fact: "startxref") else { return .noMatch }
    let declared = snapshot.evidence.startCrossReferences.last
    if let declared,
      snapshot.evidence.classicCrossReferenceCandidates.contains(declared.value)
    {
      return .proposals([
        proposal(
          offset: declared.value,
          classification: .byteExact,
          ranges: [declared.keywordRange, declared.valueRange],
          message: "The terminal startxref offset was confirmed.",
          acceptsMismatch: false
        )
      ])
    }
    let candidates = snapshot.evidence.classicCrossReferenceCandidates
    guard !candidates.isEmpty else {
      return .unrecoverable(
        .init(offset: declared?.valueRange.offset ?? 0, message: "Recovery found no cross-reference section.")
      )
    }
    if candidates.count == 1, let candidate = candidates.first {
      return .proposals([
        proposal(
          offset: candidate,
          classification: .structuralRepair,
          ranges: evidenceRanges(declared, candidate: candidate),
          message: declared == nil
            ? "A unique cross-reference section replaced a missing startxref entry."
            : "A unique cross-reference section replaced an invalid startxref offset.",
          acceptsMismatch: true
        )
      ])
    }
    guard snapshot.policy == .compatible, let candidate = candidates.last else {
      return .unrecoverable(
        .init(offset: declared?.valueRange.offset ?? 0, message: "Multiple cross-reference sections are plausible.")
      )
    }
    return .proposals([
      proposal(
        offset: candidate,
        classification: .semanticInference,
        ranges: evidenceRanges(declared, candidate: candidate),
        message: "Compatibility recovery selected the last cross-reference section.",
        acceptsMismatch: true
      )
    ])
  }

  private func proposal(
    offset: Int64,
    classification: PDFRecoveryClassification,
    ranges: [PDFSourceRange],
    message: String,
    acceptsMismatch: Bool
  ) -> PDFRecoveryProposal {
    .init(
      fact: "startxref",
      kind: .startCrossReference,
      classification: classification,
      sourceRanges: ranges,
      message: message,
      mutation: .startCrossReference(
        offset: offset,
        acceptsMismatchedFooter: acceptsMismatch
      )
    )
  }

  private func evidenceRanges(
    _ declared: PDFRecoveryStartCrossReference?,
    candidate: Int64
  ) -> [PDFSourceRange] {
    var ranges = declared.map { [$0.keywordRange, $0.valueRange] } ?? []
    ranges.append(.init(uncheckedOffset: candidate, length: 4))
    return ranges
  }
}
