import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceReportTests {
  @Test func digestMatchesPublishedSHA256Vector() {
    #expect(
      ConformanceDigest.sha256(Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  @Test func reportsHaveDeterministicOrderingAndStatuses() throws {
    let report = ConformanceRunReport(
      suite: "owned",
      results: [
        ConformanceCaseResult(id: "z", status: .passed, durationMilliseconds: 1),
        ConformanceCaseResult(id: "a", status: .difference, durationMilliseconds: 2),
      ]
    )

    #expect(report.results.map(\.id) == ["a", "z"])
    #expect(report.exitStatus == 2)
    #expect(String(decoding: try report.encodedJSON(), as: UTF8.self).contains("\"schemaVersion\" : 1"))
    #expect(String(decoding: report.encodedJUnit(), as: UTF8.self).contains("failures=\"1\""))
  }
}
