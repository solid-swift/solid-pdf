package struct PDFStreamBoundaryRecoveryPass: PDFRecoveryPass {
  package let descriptor = PDFRecoveryPassDescriptor(
    identifier: "stream.recover-boundary",
    stage: .streamBoundaries,
    priority: 100,
    invalidates: [.documentStructure, .finalValidation]
  )

  package init() {}

  package func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    guard let plan = snapshot.model.reconstructedCrossReference else { return .noMatch }
    let proposals = plan.boundaries.values.compactMap { boundary -> PDFRecoveryProposal? in
      guard let repair = boundary.repair, repair.kind == .streamBoundary else { return nil }
      let fact = "stream-boundary-\(boundary.reference.objectNumber)-\(boundary.reference.generationNumber)"
      guard !snapshot.model.contains(fact: fact) else { return nil }
      return PDFRecoveryProposal(
        fact: fact,
        kind: repair.kind,
        classification: repair.classification,
        sourceRanges: repair.sourceRanges,
        object: boundary.reference,
        message: repair.message,
        mutation: .recordedFact(fact)
      )
    }
    return proposals.isEmpty ? .noMatch : .proposals(proposals)
  }
}
