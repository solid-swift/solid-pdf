import Foundation

package struct ConformanceDiscoveryCaseResult: Codable, Sendable, Hashable {
  package let id: String
  package let source: String
  package let sourceDigest: String
  package let outcome: ConformanceDiscoveryOutcome
  package let durationMilliseconds: Int
  package let solid: ConformanceObservationResult?
  package let reference: ConformanceObservationResult?
  package let differences: [String]
  package let diagnostic: String?
  package let artifactPaths: [String]

  package init(
    id: String,
    source: String,
    sourceDigest: String,
    outcome: ConformanceDiscoveryOutcome,
    durationMilliseconds: Int,
    solid: ConformanceObservationResult? = nil,
    reference: ConformanceObservationResult? = nil,
    differences: [String] = [],
    diagnostic: String? = nil,
    artifactPaths: [String] = []
  ) {
    self.id = id
    self.source = source
    self.sourceDigest = sourceDigest
    self.outcome = outcome
    self.durationMilliseconds = durationMilliseconds
    self.solid = solid
    self.reference = reference
    self.differences = differences
    self.diagnostic = diagnostic
    self.artifactPaths = artifactPaths
  }
}
