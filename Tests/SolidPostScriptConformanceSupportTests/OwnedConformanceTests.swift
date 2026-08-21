import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite(.serialized) struct OwnedConformanceTests {
  @Test func ownedSolidExpectationsPass() async throws {
    let suite = try ConformanceSuite.load(from: Self.suiteURL)

    for testCase in suite.manifest.cases where !testCase.observations.contains(.raster) {
      do {
        let observation = try await SolidConformanceRunner.run(testCase, in: suite)
        let result = try ConformanceAdjudicator.evaluate(testCase, suite: suite, solid: observation)
        #expect(result.status == .passed, "\(testCase.id): \(result.differences)")
      } catch {
        Issue.record("\(testCase.id): \(error)")
      }
    }
  }

  private static let suiteURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Fixtures/PostScriptConformance/suite.json")
}
