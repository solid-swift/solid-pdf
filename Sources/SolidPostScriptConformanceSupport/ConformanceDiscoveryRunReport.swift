import Foundation

package struct ConformanceDiscoveryRunReport: Codable, Sendable, Hashable {
  package let schemaVersion: Int
  package let suite: String
  package let referenceVersion: String
  package let selectedSources: [String]
  package let baselineApplied: Bool
  package let baselineDifferences: [String]
  package let results: [ConformanceDiscoveryCaseResult]

  package init(
    suite: String,
    referenceVersion: String,
    selectedSources: [String]? = nil,
    baselineApplied: Bool = false,
    baselineDifferences: [String] = [],
    results: [ConformanceDiscoveryCaseResult]
  ) {
    schemaVersion = 2
    self.suite = suite
    self.referenceVersion = referenceVersion
    self.selectedSources = selectedSources ?? results.map(\.source).sorted()
    self.baselineApplied = baselineApplied
    self.baselineDifferences = baselineDifferences
    self.results = results.sorted { $0.id < $1.id }
  }

  package var exitStatus: Int32 {
    if results.contains(where: { $0.outcome == .harnessFailure }) { return 70 }
    if baselineApplied { return baselineDifferences.isEmpty ? 0 : 2 }
    if results.contains(where: { $0.outcome != .equivalent }) { return 2 }
    return 0
  }

  package func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self) + Data([0x0A])
  }

  package func encodedJUnit() -> Data {
    let resultFailures = results.filter { result in
      if result.outcome == .harnessFailure { return true }
      if baselineApplied { return result.baselineComparison != .matched }
      return result.outcome != .equivalent
    }.count
    let baselineFailure = baselineDifferences.isEmpty ? 0 : 1
    let failures = resultFailures + baselineFailure
    let cases = results.map { result in
      let body: String
      if result.outcome == .harnessFailure {
        let message = Self.xmlEscape(result.diagnostic ?? "discovery harness failed")
        body = "<failure message=\"\(message)\"/>"
      } else if baselineApplied, result.baselineComparison == .matched, result.outcome != .equivalent {
        let classification = result.baselineClassification?.rawValue ?? result.outcome.rawValue
        body = "<skipped message=\"known observational outcome: \(Self.xmlEscape(classification))\"/>"
      } else if baselineApplied, result.baselineComparison != .matched {
        body = "<failure message=\"discovery outcome differs from baseline\"/>"
      } else if result.outcome == .equivalent {
        body = ""
      } else {
        let message = Self.xmlEscape(
          (result.differences + [result.diagnostic].compactMap { $0 }).joined(separator: "; ")
        )
        body = "<failure message=\"\(message)\"/>"
      }
      return "  <testcase classname=\"PostScriptDiscovery\" name=\"\(Self.xmlEscape(result.id))\" time=\"\(Double(result.durationMilliseconds) / 1_000)\">\(body)</testcase>"
    }
    var allCases = cases
    if !baselineDifferences.isEmpty {
      let message = Self.xmlEscape(baselineDifferences.joined(separator: "; "))
      allCases.append(
        "  <testcase classname=\"PostScriptDiscovery\" name=\"baseline\" time=\"0\"><failure message=\"\(message)\"/></testcase>"
      )
    }
    return Data(
      "<testsuite name=\"\(Self.xmlEscape(suite))\" tests=\"\(allCases.count)\" failures=\"\(failures)\">\n\(allCases.joined(separator: "\n"))\n</testsuite>\n".utf8
    )
  }

  private static func xmlEscape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
