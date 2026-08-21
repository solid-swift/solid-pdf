import Foundation

package struct ConformanceSuite: Sendable {
  package let manifest: ConformanceSuiteManifest
  package let root: URL

  package static func load(from manifestURL: URL) throws -> Self {
    let standardizedURL = manifestURL.standardizedFileURL
    let root = standardizedURL.deletingLastPathComponent().resolvingSymlinksInPath()
    let data = try Data(contentsOf: standardizedURL, options: [.mappedIfSafe])
    let manifest = try JSONDecoder().decode(ConformanceSuiteManifest.self, from: data)
    guard manifest.schemaVersion == 1 else {
      throw ConformanceError.invalidManifest("unsupported schema version \(manifest.schemaVersion)")
    }
    guard !manifest.name.isEmpty else { throw ConformanceError.invalidManifest("suite name is empty") }

    var identifiers = Set<String>()
    for testCase in manifest.cases {
      guard Self.validIdentifier(testCase.id), identifiers.insert(testCase.id).inserted else {
        throw ConformanceError.invalidManifest("invalid or duplicate case id \(testCase.id)")
      }
      guard !testCase.title.isEmpty, !testCase.authority.isEmpty,
        testCase.authority.allSatisfy({ !$0.document.isEmpty && !$0.section.isEmpty })
      else { throw ConformanceError.invalidManifest("case \(testCase.id) lacks authority or title") }
      guard !testCase.observations.isEmpty else {
        throw ConformanceError.invalidManifest("case \(testCase.id) has no observations")
      }
      try Self.validate(limits: testCase.limits, id: testCase.id)
      _ = try Self.resolve(testCase.source, beneath: root)
      if let transcript = testCase.expectation?.solid?.transcript {
        _ = try Self.resolve(transcript, beneath: root)
      }
      if let transcript = testCase.expectation?.reference?.transcript {
        _ = try Self.resolve(transcript, beneath: root)
      }
      try Self.validate(disposition: testCase.disposition, expectation: testCase.expectation, id: testCase.id)
      if testCase.rasterTolerance != .default,
        testCase.rasterTolerance.rationale?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
      {
        throw ConformanceError.invalidManifest("case \(testCase.id) overrides raster tolerance without a rationale")
      }
    }
    return Self(manifest: manifest, root: root)
  }

  package func sourceURL(for testCase: ConformanceCaseManifest) throws -> URL {
    try Self.resolve(testCase.source, beneath: root)
  }

  package func expectedTranscript(for testCase: ConformanceCaseManifest) throws -> Data? {
    guard let path = testCase.expectation?.solid?.transcript else { return nil }
    return try expectedTranscript(path: path)
  }

  package func expectedTranscript(path: String) throws -> Data {
    try Data(contentsOf: Self.resolve(path, beneath: root), options: [.mappedIfSafe])
  }

  private static func validate(
    disposition: ConformanceDisposition,
    expectation: ConformanceExpectation?,
    id: String
  ) throws {
    switch disposition {
    case .equivalent:
      break
    case .solidExpected:
      guard expectation?.solid != nil else {
        throw ConformanceError.invalidManifest("case \(id) requires a Solid expectation")
      }
    case .acceptedDifference:
      guard let expectation,
        expectation.solid != nil,
        expectation.reference != nil,
        expectation.referenceVersion?.isEmpty == false,
        expectation.rationale?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      else { throw ConformanceError.invalidManifest("case \(id) has an incomplete accepted difference") }
    case .discovery:
      break
    }
  }

  private static func validate(limits: ConformanceLimits, id: String) throws {
    guard limits.timeoutMilliseconds > 0,
      limits.maximumInputBytes > 0,
      limits.maximumTranscriptBytes > 0,
      limits.maximumRasterPixels > 0,
      limits.maximumTemporaryBytes > 0
    else { throw ConformanceError.invalidManifest("case \(id) has nonpositive limits") }
  }

  private static func resolve(_ path: String, beneath root: URL) throws -> URL {
    guard !path.isEmpty else { throw ConformanceError.invalidPath(path) }
    let candidate = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard candidate.path.hasPrefix(prefix), FileManager.default.fileExists(atPath: candidate.path) else {
      throw ConformanceError.invalidPath(path)
    }
    return candidate
  }

  private static func validIdentifier(_ value: String) -> Bool {
    guard let first = value.first, first.isASCII, first.isLetter || first.isNumber else { return false }
    return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
  }
}
