import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceDiscoveryReportTests {
  @Test func reservesHarnessFailureForInfrastructureFailures() {
    let timeout = result(id: "timeout", outcome: .executionLimit)
    let difference = result(id: "difference", outcome: .compatibilityDifference)
    let harness = result(id: "harness", outcome: .harnessFailure)

    #expect(report([timeout]).exitStatus == 2)
    #expect(report([difference]).exitStatus == 2)
    #expect(report([harness]).exitStatus == 70)
    #expect(report([result(id: "pass", outcome: .equivalent)]).exitStatus == 0)
  }

  @Test func reportsDiscoveryFailuresWithoutPlatformSpecificPaths() throws {
    let diagnostic = ConformanceDiscoveryDiagnostic.normalize(
      "runner detail\nError: invalidFont /private/tmp/font.pfb\n",
      prefix: "Solid execution failed"
    )
    let value = result(
      id: "font",
      outcome: .compatibilityDifference,
      diagnostic: diagnostic
    )
    let run = report([value])
    let json = String(decoding: try run.encodedJSON(), as: UTF8.self)
    let junit = String(decoding: run.encodedJUnit(), as: UTF8.self)

    #expect(diagnostic == "Solid execution failed: Error: invalidFont <path>")
    #expect(!json.contains("/private/tmp"))
    #expect(junit.contains("failures=\"1\""))
  }

  @Test func matchedKnownOutcomesRemainVisibleWithoutFailingTheGate() {
    let known = result(
      id: "known",
      outcome: .compatibilityDifference,
      baselineClassification: .unavailablePrerequisite,
      baselineComparison: .matched
    )
    let run = ConformanceDiscoveryRunReport(
      suite: "external",
      referenceVersion: "10.07.1",
      baselineApplied: true,
      results: [known]
    )
    let junit = String(decoding: run.encodedJUnit(), as: UTF8.self)

    #expect(run.exitStatus == 0)
    #expect(junit.contains("<skipped message=\"known observational outcome: unavailablePrerequisite\"/>"))
    #expect(junit.contains("failures=\"0\""))
  }

  @Test func baselineDriftFailsWithStatusTwo() {
    let changed = result(
      id: "changed",
      outcome: .compatibilityDifference,
      baselineComparison: .changed
    )
    let run = ConformanceDiscoveryRunReport(
      suite: "external",
      referenceVersion: "10.07.1",
      baselineApplied: true,
      baselineDifferences: ["discovery outcome changed: changed.ps"],
      results: [changed]
    )

    #expect(run.exitStatus == 2)
    #expect(String(decoding: run.encodedJUnit(), as: UTF8.self).contains("name=\"baseline\""))
  }

  private func report(_ results: [ConformanceDiscoveryCaseResult]) -> ConformanceDiscoveryRunReport {
    ConformanceDiscoveryRunReport(
      suite: "external",
      referenceVersion: "10.07.1",
      results: results
    )
  }

  private func result(
    id: String,
    outcome: ConformanceDiscoveryOutcome,
    diagnostic: String? = nil,
    baselineClassification: ConformanceDiscoveryOutcome? = nil,
    baselineComparison: ConformanceDiscoveryBaselineComparison? = nil
  ) -> ConformanceDiscoveryCaseResult {
    ConformanceDiscoveryCaseResult(
      id: id,
      source: "\(id).ps",
      sourceDigest: String(repeating: "0", count: 64),
      outcome: outcome,
      durationMilliseconds: 1,
      diagnostic: diagnostic,
      baselineClassification: baselineClassification,
      baselineComparison: baselineComparison
    )
  }
}
