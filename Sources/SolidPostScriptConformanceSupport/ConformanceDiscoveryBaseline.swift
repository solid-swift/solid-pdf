import Foundation

package struct ConformanceDiscoveryBaseline: Codable, Sendable, Hashable {
  package struct Entry: Codable, Sendable, Hashable {
    package let id: String
    package let source: String
    package let sourceDigest: String
    package let outcomeFingerprint: String
    package let classification: ConformanceDiscoveryOutcome
    package let rationale: String?
    package let ownedRegression: String?

    package init(
      id: String,
      source: String,
      sourceDigest: String,
      outcomeFingerprint: String,
      classification: ConformanceDiscoveryOutcome,
      rationale: String? = nil,
      ownedRegression: String? = nil
    ) {
      self.id = id
      self.source = source
      self.sourceDigest = sourceDigest
      self.outcomeFingerprint = outcomeFingerprint
      self.classification = classification
      self.rationale = rationale
      self.ownedRegression = ownedRegression
    }
  }

  package struct Evaluation: Sendable, Hashable {
    package let results: [ConformanceDiscoveryCaseResult]
    package let differences: [String]
  }

  package let schemaVersion: Int
  package let corpusVersion: String
  package let referenceVersion: String
  package let referenceArchiveSHA256: String
  package let selectionLimit: Int
  package let entries: [Entry]

  package init(
    schemaVersion: Int = 1,
    corpusVersion: String,
    referenceVersion: String,
    referenceArchiveSHA256: String,
    selectionLimit: Int,
    entries: [Entry]
  ) {
    self.schemaVersion = schemaVersion
    self.corpusVersion = corpusVersion
    self.referenceVersion = referenceVersion
    self.referenceArchiveSHA256 = referenceArchiveSHA256
    self.selectionLimit = selectionLimit
    self.entries = entries
  }

  package static func load(from url: URL) throws -> Self {
    let data: Data
    do {
      data = try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
      throw ConformanceError.invalidPath(url.path)
    }
    let baseline: Self
    do {
      baseline = try JSONDecoder().decode(Self.self, from: data)
    } catch {
      throw ConformanceError.invalidManifest("invalid discovery baseline: \(error)")
    }
    try baseline.validate()
    return baseline
  }

  package static func candidate(
    corpusVersion: String,
    referenceVersion: String,
    referenceArchiveSHA256: String,
    selectionLimit: Int,
    selectedSources: [String],
    results: [ConformanceDiscoveryCaseResult]
  ) throws -> Self {
    let bySource = Dictionary(uniqueKeysWithValues: results.map { ($0.source, $0) })
    return try Self(
      corpusVersion: corpusVersion,
      referenceVersion: referenceVersion,
      referenceArchiveSHA256: referenceArchiveSHA256,
      selectionLimit: selectionLimit,
      entries: selectedSources.compactMap { source in
        guard let result = bySource[source] else { return nil }
        return try Entry(
          id: result.id,
          source: source,
          sourceDigest: result.sourceDigest,
          outcomeFingerprint: ConformanceDiscoveryFingerprint.digest(result),
          classification: result.outcome
        )
      }
    )
  }

  package func evaluate(
    results: [ConformanceDiscoveryCaseResult],
    selectedSources: [String],
    referenceVersion actualReferenceVersion: String,
    referenceArchiveSHA256 actualArchiveSHA256: String,
    selectionLimit actualSelectionLimit: Int
  ) throws -> Evaluation {
    var differences: [String] = []
    if referenceVersion != actualReferenceVersion {
      differences.append("reference version changed from \(referenceVersion) to \(actualReferenceVersion)")
    }
    if referenceArchiveSHA256 != actualArchiveSHA256 {
      differences.append("reference archive checksum changed")
    }
    if selectionLimit != actualSelectionLimit {
      differences.append("selection limit changed from \(selectionLimit) to \(actualSelectionLimit)")
    }
    if entries.map(\.source) != selectedSources {
      differences.append("selected external sources changed or were reordered")
    }

    let baselineBySource = Dictionary(uniqueKeysWithValues: entries.map { ($0.source, $0) })
    let actualSources = Set(results.map(\.source))
    for entry in entries where !actualSources.contains(entry.source) {
      differences.append("baseline source is missing: \(entry.source)")
    }
    var evaluated: [ConformanceDiscoveryCaseResult] = []
    for result in results {
      guard let entry = baselineBySource[result.source] else {
        differences.append("new discovery source: \(result.source)")
        evaluated.append(result.withBaseline(comparison: .new))
        continue
      }
      let fingerprint = try ConformanceDiscoveryFingerprint.digest(result)
      let matched = entry.id == result.id
        && entry.sourceDigest == result.sourceDigest
        && entry.outcomeFingerprint == fingerprint
      if !matched { differences.append("discovery outcome changed: \(result.source)") }
      evaluated.append(
        result.withBaseline(
          classification: entry.classification,
          comparison: matched ? .matched : .changed,
          ownedRegression: entry.ownedRegression
        )
      )
    }
    return Evaluation(results: evaluated, differences: differences)
  }

  package func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self) + Data([0x0A])
  }

  private func validate() throws {
    guard schemaVersion == 1 else {
      throw ConformanceError.invalidManifest("unsupported discovery baseline schema \(schemaVersion)")
    }
    guard !corpusVersion.isEmpty, !referenceVersion.isEmpty, selectionLimit > 0,
      Self.isSHA256(referenceArchiveSHA256)
    else { throw ConformanceError.invalidManifest("discovery baseline metadata is invalid") }
    guard entries.count <= selectionLimit else {
      throw ConformanceError.invalidManifest("discovery baseline exceeds its selection limit")
    }
    var identifiers = Set<String>()
    var sources = Set<String>()
    for entry in entries {
      guard !entry.id.isEmpty, identifiers.insert(entry.id).inserted,
        !entry.source.isEmpty, sources.insert(entry.source).inserted,
        Self.isSHA256(entry.sourceDigest), Self.isSHA256(entry.outcomeFingerprint),
        entry.classification != .harnessFailure
      else { throw ConformanceError.invalidManifest("discovery baseline entry is invalid: \(entry.source)") }
      if entry.classification != .equivalent,
        entry.rationale?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
      {
        throw ConformanceError.invalidManifest("discovery baseline entry lacks a rationale: \(entry.source)")
      }
    }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }
}

private extension ConformanceDiscoveryCaseResult {
  func withBaseline(
    classification: ConformanceDiscoveryOutcome? = nil,
    comparison: ConformanceDiscoveryBaselineComparison,
    ownedRegression: String? = nil
  ) -> Self {
    Self(
      id: id,
      source: source,
      sourceDigest: sourceDigest,
      outcome: outcome,
      durationMilliseconds: durationMilliseconds,
      solid: solid,
      reference: reference,
      differences: differences,
      diagnostic: diagnostic,
      artifactPaths: artifactPaths,
      baselineClassification: classification,
      baselineComparison: comparison,
      ownedRegression: ownedRegression
    )
  }
}
