import Foundation

package struct ConformanceObservationResult: Codable, Sendable, Hashable {
  package let transcript: Data?
  package let recordingDigest: String?
  package let rasterDigests: [String]

  package init(transcript: Data? = nil, recordingDigest: String? = nil, rasterDigests: [String] = []) {
    self.transcript = transcript
    self.recordingDigest = recordingDigest
    self.rasterDigests = rasterDigests
  }
}

package struct ConformanceCaseResult: Codable, Sendable, Hashable {
  package enum Status: String, Codable, Sendable, Hashable {
    case passed
    case failed
    case difference
    case harnessFailure
  }

  package let id: String
  package let status: Status
  package let durationMilliseconds: Int
  package let solid: ConformanceObservationResult?
  package let reference: ConformanceObservationResult?
  package let differences: [String]
  package let diagnostic: String?

  package init(
    id: String,
    status: Status,
    durationMilliseconds: Int,
    solid: ConformanceObservationResult? = nil,
    reference: ConformanceObservationResult? = nil,
    differences: [String] = [],
    diagnostic: String? = nil
  ) {
    self.id = id
    self.status = status
    self.durationMilliseconds = durationMilliseconds
    self.solid = solid
    self.reference = reference
    self.differences = differences
    self.diagnostic = diagnostic
  }
}

package struct ConformanceRunReport: Codable, Sendable, Hashable {
  package let schemaVersion: Int
  package let suite: String
  package let referenceVersion: String?
  package let results: [ConformanceCaseResult]

  package init(suite: String, referenceVersion: String? = nil, results: [ConformanceCaseResult]) {
    schemaVersion = 1
    self.suite = suite
    self.referenceVersion = referenceVersion
    self.results = results.sorted { $0.id < $1.id }
  }

  package var exitStatus: Int32 {
    if results.contains(where: { $0.status == .harnessFailure }) { return 70 }
    if results.contains(where: { $0.status == .failed }) { return 1 }
    if results.contains(where: { $0.status == .difference }) { return 2 }
    return 0
  }

  package func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self) + Data([0x0A])
  }

  package func encodedJUnit() -> Data {
    let failures = results.filter { $0.status != .passed }.count
    let cases = results.map { result in
      let body: String
      if result.status == .passed {
        body = ""
      } else {
        let message = Self.xmlEscape((result.differences + [result.diagnostic].compactMap { $0 }).joined(separator: "; "))
        body = "<failure message=\"\(message)\"/>"
      }
      return "  <testcase classname=\"PostScriptConformance\" name=\"\(Self.xmlEscape(result.id))\" time=\"\(Double(result.durationMilliseconds) / 1_000)\">\(body)</testcase>"
    }.joined(separator: "\n")
    return Data("<testsuite name=\"\(Self.xmlEscape(suite))\" tests=\"\(results.count)\" failures=\"\(failures)\">\n\(cases)\n</testsuite>\n".utf8)
  }

  private static func xmlEscape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
