package enum ConformanceDiscoveryOutcome: String, Codable, Sendable, Hashable {
  case equivalent
  case compatibilityDifference
  case unavailablePrerequisite
  case executionLimit
  case harnessFailure
}
