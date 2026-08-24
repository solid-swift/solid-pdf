import Foundation

package enum ConformanceDiscoveryFingerprint {
  package static func digest(_ result: ConformanceDiscoveryCaseResult) throws -> String {
    let canonical = CanonicalResult(
      outcome: result.outcome,
      solid: result.solid,
      reference: result.reference,
      differences: result.differences,
      diagnostic: result.diagnostic
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return ConformanceDigest.sha256(try encoder.encode(canonical))
  }

  private struct CanonicalResult: Codable {
    let outcome: ConformanceDiscoveryOutcome
    let solid: ConformanceObservationResult?
    let reference: ConformanceObservationResult?
    let differences: [String]
    let diagnostic: String?
  }
}
