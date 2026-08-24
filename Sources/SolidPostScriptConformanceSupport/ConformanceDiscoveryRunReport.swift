import Foundation

package struct ConformanceDiscoveryRunReport: Codable, Sendable, Hashable {
  package let schemaVersion: Int
  package let suite: String
  package let referenceVersion: String
  package let results: [ConformanceDiscoveryCaseResult]

  package init(
    suite: String,
    referenceVersion: String,
    results: [ConformanceDiscoveryCaseResult]
  ) {
    schemaVersion = 1
    self.suite = suite
    self.referenceVersion = referenceVersion
    self.results = results.sorted { $0.id < $1.id }
  }

  package var exitStatus: Int32 {
    if results.contains(where: { $0.outcome == .harnessFailure }) { return 70 }
    if results.contains(where: { $0.outcome != .equivalent }) { return 2 }
    return 0
  }

  package func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self) + Data([0x0A])
  }

  package func encodedJUnit() -> Data {
    let failures = results.filter { $0.outcome != .equivalent }.count
    let cases = results.map { result in
      let body: String
      if result.outcome == .equivalent {
        body = ""
      } else {
        let message = Self.xmlEscape(
          (result.differences + [result.diagnostic].compactMap { $0 }).joined(separator: "; ")
        )
        body = "<failure message=\"\(message)\"/>"
      }
      return "  <testcase classname=\"PostScriptDiscovery\" name=\"\(Self.xmlEscape(result.id))\" time=\"\(Double(result.durationMilliseconds) / 1_000)\">\(body)</testcase>"
    }.joined(separator: "\n")
    return Data(
      "<testsuite name=\"\(Self.xmlEscape(suite))\" tests=\"\(results.count)\" failures=\"\(failures)\">\n\(cases)\n</testsuite>\n".utf8
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
