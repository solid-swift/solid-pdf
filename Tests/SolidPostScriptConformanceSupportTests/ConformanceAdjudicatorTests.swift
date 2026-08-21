import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceAdjudicatorTests {
  @Test func acceptsOnlyThePinnedReferenceResultAndVersion() throws {
    let temporary = FileManager.default.temporaryDirectory
      .appending(path: "conformance-adjudicator-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Data().write(to: temporary.appending(path: "case.ps"))
    try transcript(value: 3).write(to: temporary.appending(path: "solid.transcript"))
    try transcript(value: 2).write(to: temporary.appending(path: "reference.transcript"))
    let testCase = ConformanceCaseManifest(
      id: "errors.stack",
      title: "Error stack",
      authority: [ConformanceAuthority(section: "3.11.1")],
      source: "case.ps",
      disposition: .acceptedDifference,
      expectation: ConformanceExpectation(
        solid: ConformanceExpectedResult(transcript: "solid.transcript"),
        reference: ConformanceExpectedResult(transcript: "reference.transcript"),
        referenceVersion: "10.07.1",
        rationale: "PLRM-adjudicated difference"
      )
    )
    try JSONEncoder().encode(ConformanceSuiteManifest(name: "unit", cases: [testCase]))
      .write(to: temporary.appending(path: "suite.json"))
    let suite = try ConformanceSuite.load(from: temporary.appending(path: "suite.json"))
    let loadedCase = try #require(suite.manifest.cases.first)
    let solid = ConformanceObservationResult(transcript: transcript(value: 3))
    let reference = ConformanceObservationResult(transcript: transcript(value: 2))

    let accepted = try ConformanceAdjudicator.evaluate(
      loadedCase,
      suite: suite,
      solid: solid,
      reference: reference,
      referenceVersion: "10.07.1"
    )
    let stale = try ConformanceAdjudicator.evaluate(
      loadedCase,
      suite: suite,
      solid: solid,
      reference: reference,
      referenceVersion: "10.07.2"
    )

    #expect(accepted.status == .passed)
    #expect(stale.status == .difference)
    #expect(stale.differences == ["accepted reference version is stale or unavailable"])
  }

  private func transcript(value: Int) -> Data {
    Data("SPS-CONFORMANCE 1\nV 737461636b integer \(value)\n".utf8)
  }
}
