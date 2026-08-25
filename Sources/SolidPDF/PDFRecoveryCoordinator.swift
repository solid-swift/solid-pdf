package struct PDFRecoveryCoordinator: Sendable {
  private let options: PDFRecoveryOptions
  private let registry: PDFRecoveryRegistry

  package init(
    options: PDFRecoveryOptions,
    registry: PDFRecoveryRegistry? = nil
  ) throws {
    try options.limits.validate()
    self.options = options
    self.registry = try registry ?? .builtIn
  }

  func recover<Session: PDFInputSourceSession>(
    reader: PDFSourceReader<Session>,
    strictError: PDFParsingError,
    parsingOptions: PDFParsingOptions
  ) async throws -> PDFCrossReferenceIndex {
    let strictFailure = Self.diagnostic(from: strictError)
    let length = try await reader.length()
    let source = PDFRecoverySource(reader: reader, length: length)
    let evidence = try await PDFRecoveryEvidence.collect(from: source, limits: options.limits)
    var model = PDFRecoveryModel()
    var records = [PDFRecoveryRecord]()
    var unresolved = [PDFParsingDiagnostic]()
    var proposalCount = 0
    var generation = 0
    try await runPasses(
      source: source,
      evidence: evidence,
      parsingLimits: parsingOptions.limits,
      model: &model,
      records: &records,
      unresolved: &unresolved,
      proposalCount: &proposalCount,
      generation: &generation
    )
    guard let headerOffset = model.headerOffset,
      let version = model.version,
      model.endOffset != nil,
      let startCrossReferenceOffset = model.startCrossReferenceOffset
    else {
      throw PDFParsingError.malformed(
        unresolved.first ?? .init(offset: 0, message: "Recovery could not establish document framing.")
      )
    }
    let strictOptions = PDFParsingOptions(
      limits: parsingOptions.limits,
      sourceWindowByteCount: parsingOptions.sourceWindowByteCount,
      decodedStreamChunkByteCount: parsingOptions.decodedStreamChunkByteCount,
      acceptsStreamFilterAbbreviations: parsingOptions.acceptsStreamFilterAbbreviations,
      recovery: nil
    )
    let initialReport = makeReport(
      strictFailure: strictFailure,
      records: records,
      unresolved: unresolved
    )
    let overrides = PDFCrossReferenceParsingOverrides(
      headerOffset: headerOffset,
      version: version,
      latestCrossReferenceOffset: startCrossReferenceOffset,
      acceptsMismatchedFooter: model.acceptsMismatchedFooter,
      acceptsMissingEndOfFile: model.acceptsMissingEndOfFile,
      recoveryReport: initialReport
    )
    do {
      let index = try await PDFCrossReferenceParser(
        reader: reader,
        options: strictOptions,
        overrides: overrides
      ).parse()
      try await PDFRecoveryStrictPreflight.validate(
        index: index,
        reader: reader,
        limits: parsingOptions.limits
      )
      return index
    } catch let crossReferenceError as PDFParsingError {
      model.crossReferenceFailure = Self.diagnostic(from: crossReferenceError)
      try await runPasses(
        source: source,
        evidence: evidence,
        parsingLimits: parsingOptions.limits,
        model: &model,
        records: &records,
        unresolved: &unresolved,
        proposalCount: &proposalCount,
        generation: &generation
      )
      guard let plan = model.reconstructedCrossReference else { throw crossReferenceError }
      let report = makeReport(
        strictFailure: strictFailure,
        records: records,
        unresolved: unresolved
      )
      return try PDFCrossReferenceIndex.recovered(plan: plan, report: report)
    }
  }

  private func runPasses(
    source: PDFRecoverySource,
    evidence: PDFRecoveryEvidence,
    parsingLimits: PDFParsingLimits,
    model: inout PDFRecoveryModel,
    records: inout [PDFRecoveryRecord],
    unresolved: inout [PDFParsingDiagnostic],
    proposalCount: inout Int,
    generation: inout Int
  ) async throws {
    while generation < options.limits.maximumPassGenerations {
      try Task.checkCancellation()
      let snapshot = PDFRecoverySnapshot(
        source: source,
        policy: options.policy,
        limits: options.limits,
        parsingLimits: parsingLimits,
        evidence: evidence,
        model: model,
        generation: generation
      )
      var changed = false
      for stage in PDFRecoveryStage.allCases {
        var proposalsByFact = [String: [(PDFRecoveryPassDescriptor, PDFRecoveryProposal)]]()
        for pass in registry.passes where pass.descriptor.stage == stage
          && Self.permits(options.policy, minimum: pass.descriptor.minimumPolicy)
        {
          switch try await pass.evaluate(snapshot) {
          case .noMatch:
            continue
          case .unrecoverable(let diagnostic):
            guard unresolved.count < options.limits.maximumAmbiguities else {
              throw PDFParsingError.limitExceeded(
                .init(offset: diagnostic.offset, message: "Recovery retained too many unresolved ambiguities.")
              )
            }
            unresolved.append(diagnostic)
          case .proposals(let proposals):
            proposalCount += proposals.count
            guard proposalCount <= options.limits.maximumProposals else {
              throw PDFParsingError.limitExceeded(
                .init(offset: 0, message: "Recovery produced too many proposals.")
              )
            }
            for proposal in proposals where !model.contains(fact: proposal.fact) {
              proposalsByFact[proposal.fact, default: []].append((pass.descriptor, proposal))
            }
          }
        }
        for fact in proposalsByFact.keys.sorted() {
          guard let candidates = proposalsByFact[fact], !candidates.isEmpty else { continue }
          let selected = try select(candidates, policy: options.policy)
          model.apply(selected.mutation)
          changed = true
          if selected.classification != .byteExact {
            guard records.count < options.limits.maximumAppliedRecords else {
              throw PDFParsingError.limitExceeded(
                .init(offset: 0, message: "Recovery applied too many repairs.")
              )
            }
            records.append(
              .init(
                identifier: .init(ordinal: records.count),
                kind: selected.kind,
                classification: selected.classification,
                sourceRanges: selected.sourceRanges,
                object: selected.object,
                message: selected.message
              )
            )
          }
        }
      }
      if !changed { break }
      generation += 1
    }
    guard generation < options.limits.maximumPassGenerations else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "Recovery did not converge within its generation limit.")
      )
    }
  }

  private func makeReport(
    strictFailure: PDFParsingDiagnostic,
    records: [PDFRecoveryRecord],
    unresolved: [PDFParsingDiagnostic]
  ) -> PDFRecoveryReport {
    let hasInference = records.contains { $0.classification == .semanticInference }
    return PDFRecoveryReport(
      policy: options.policy,
      strictFailure: strictFailure,
      records: records,
      unresolvedDamage: unresolved,
      incrementalWriting: records.isEmpty
        ? .eligible
        : .ineligible(reason: "Recovered framing requires strict staged validation before writing."),
      signatureValidation: hasInference
        ? .ineligible(reason: "Compatibility inference affected document structure.")
        : .ineligible(reason: "Recovered revision framing is not byte-exact.")
    )
  }

  private func select(
    _ candidates: [(PDFRecoveryPassDescriptor, PDFRecoveryProposal)],
    policy: PDFRecoveryPolicy
  ) throws -> PDFRecoveryProposal {
    let unique = Dictionary(grouping: candidates, by: { $0.1.mutation })
    if unique.count == 1, let proposal = candidates.first?.1 { return proposal }
    guard policy == .compatible else {
      throw PDFParsingError.malformed(
        .init(offset: 0, message: "Structural recovery produced conflicting proposals.")
      )
    }
    return candidates.sorted { lhs, rhs in
      if lhs.0.priority != rhs.0.priority { return lhs.0.priority < rhs.0.priority }
      let leftOffset = lhs.1.sourceRanges.first?.offset ?? 0
      let rightOffset = rhs.1.sourceRanges.first?.offset ?? 0
      if leftOffset != rightOffset { return leftOffset > rightOffset }
      return lhs.0.identifier < rhs.0.identifier
    }[0].1
  }

  private static func permits(
    _ selected: PDFRecoveryPolicy,
    minimum: PDFRecoveryPolicy
  ) -> Bool {
    selected == .compatible || minimum == .structural
  }

  private static func diagnostic(from error: PDFParsingError) -> PDFParsingDiagnostic {
    switch error {
    case .malformed(let diagnostic), .truncated(let diagnostic), .limitExceeded(let diagnostic),
      .sourceFailure(let diagnostic), .authenticationFailure(let diagnostic):
      diagnostic
    case .unsupported(_, let diagnostic):
      diagnostic
    default:
      .init(offset: 0, message: "Strict PDF parsing failed: \(error)")
    }
  }
}
