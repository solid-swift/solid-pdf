import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceDiscoveryBaselineTests {
  @Test func exactOutcomeMatchesWhileDurationAndArtifactsAreIgnored() throws {
    let observed = result(duration: 10, artifacts: ["artifacts/one.ppm"])
    let entry = try entry(for: observed)
    let baseline = baseline(entries: [entry])
    let repeated = result(duration: 900, artifacts: ["artifacts/two.ppm"])

    let evaluation = try baseline.evaluate(
      results: [repeated],
      selectedSources: [repeated.source],
      referenceVersion: "10.07.1",
      referenceArchiveSHA256: sha("a"),
      selectionLimit: 1
    )

    #expect(evaluation.differences.isEmpty)
    #expect(evaluation.results.first?.baselineComparison == .matched)
    #expect(evaluation.results.first?.baselineClassification == .compatibilityDifference)
  }

  @Test func detectsSourceReferenceSelectionAndOutcomeDrift() throws {
    let observed = result()
    let baseline = baseline(entries: [try entry(for: observed)])
    let changed = ConformanceDiscoveryCaseResult(
      id: observed.id,
      source: observed.source,
      sourceDigest: sha("changed-source"),
      outcome: .equivalent,
      durationMilliseconds: 1
    )

    let evaluation = try baseline.evaluate(
      results: [changed],
      selectedSources: ["new.ps"],
      referenceVersion: "changed",
      referenceArchiveSHA256: sha("changed-archive"),
      selectionLimit: 2
    )

    #expect(evaluation.results.first?.baselineComparison == .changed)
    #expect(evaluation.differences.contains(where: { $0.contains("reference version") }))
    #expect(evaluation.differences.contains(where: { $0.contains("archive checksum") }))
    #expect(evaluation.differences.contains(where: { $0.contains("selection limit") }))
    #expect(evaluation.differences.contains(where: { $0.contains("sources changed") }))
    #expect(evaluation.differences.contains(where: { $0.contains("outcome changed") }))
  }

  @Test func rejectsUnreviewedNonEquivalentBaseline() throws {
    let observed = result()
    let unreviewed = try ConformanceDiscoveryBaseline(
      corpusVersion: "test-v1",
      referenceVersion: "10.07.1",
      referenceArchiveSHA256: sha("a"),
      selectionLimit: 1,
      entries: [
        .init(
          id: observed.id,
          source: observed.source,
          sourceDigest: observed.sourceDigest,
          outcomeFingerprint: ConformanceDiscoveryFingerprint.digest(observed),
          classification: .compatibilityDifference
        )
      ]
    )
    let temporary = FileManager.default.temporaryDirectory
      .appending(path: "discovery-baseline-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try unreviewed.encodedJSON().write(to: temporary)

    #expect(throws: ConformanceError.self) {
      try ConformanceDiscoveryBaseline.load(from: temporary)
    }
  }

  @Test func candidatePreservesSelectionOrderWithoutInventingRationales() throws {
    let first = result(id: "first", source: "z.ps")
    let second = result(id: "second", source: "a.ps")

    let candidate = try ConformanceDiscoveryBaseline.candidate(
      corpusVersion: "test-v1",
      referenceVersion: "10.07.1",
      referenceArchiveSHA256: sha("a"),
      selectionLimit: 2,
      selectedSources: ["z.ps", "a.ps"],
      results: [second, first]
    )

    #expect(candidate.entries.map(\.source) == ["z.ps", "a.ps"])
    #expect(candidate.entries.allSatisfy { $0.rationale == nil })
  }

  @Test func reviewedRasterDiscoveriesReferenceOwnedCases() throws {
    let baseline = try ConformanceDiscoveryBaseline.load(from: Self.reviewedBaselineURL)
    let suite = try ConformanceSuite.load(from: Self.suiteURL)
    let ownedIdentifiers = Set(suite.manifest.cases.map(\.id))
    let regressions = baseline.entries.compactMap(\.ownedRegression)

    #expect(regressions.count == 3)
    #expect(regressions.allSatisfy(ownedIdentifiers.contains))
  }

  private func baseline(entries: [ConformanceDiscoveryBaseline.Entry]) -> ConformanceDiscoveryBaseline {
    ConformanceDiscoveryBaseline(
      corpusVersion: "test-v1",
      referenceVersion: "10.07.1",
      referenceArchiveSHA256: sha("a"),
      selectionLimit: entries.count,
      entries: entries
    )
  }

  private func entry(
    for result: ConformanceDiscoveryCaseResult
  ) throws -> ConformanceDiscoveryBaseline.Entry {
    try .init(
      id: result.id,
      source: result.source,
      sourceDigest: result.sourceDigest,
      outcomeFingerprint: ConformanceDiscoveryFingerprint.digest(result),
      classification: .compatibilityDifference,
      rationale: "Observed external compatibility difference; not PLRM adjudication."
    )
  }

  private func result(
    id: String = "case",
    source: String = "case.ps",
    duration: Int = 1,
    artifacts: [String] = []
  ) -> ConformanceDiscoveryCaseResult {
    ConformanceDiscoveryCaseResult(
      id: id,
      source: source,
      sourceDigest: sha(source),
      outcome: .compatibilityDifference,
      durationMilliseconds: duration,
      differences: ["raster differs"],
      diagnostic: "Solid execution failed: Error: invalidFont",
      artifactPaths: artifacts
    )
  }

  private func sha(_ value: String) -> String {
    ConformanceDigest.sha256(Data(value.utf8))
  }

  private static let fixtureRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Fixtures/PostScriptConformance")
  private static let suiteURL = fixtureRoot.appending(path: "suite.json")
  private static let reviewedBaselineURL = fixtureRoot
    .appending(path: "External/Ghostscript-10.07.1.discovery.json")
}
