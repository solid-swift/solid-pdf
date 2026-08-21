import Foundation

package enum ConformanceError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalidManifest(String)
  case invalidPath(String)
  case inputLimitExceeded
  case transcriptLimitExceeded
  case rasterLimitExceeded
  case malformedTranscript(String)
  case missingReference
  case unsupportedEnvironment(String)
  case processFailed(String)

  package var description: String {
    switch self {
    case .invalidManifest(let message): "invalid manifest: \(message)"
    case .invalidPath(let path): "invalid or escaping path: \(path)"
    case .inputLimitExceeded: "input limit exceeded"
    case .transcriptLimitExceeded: "transcript limit exceeded"
    case .rasterLimitExceeded: "raster limit exceeded"
    case .malformedTranscript(let message): "malformed transcript: \(message)"
    case .missingReference: "Ghostscript reference executable is unavailable"
    case .unsupportedEnvironment(let environment): "unsupported conformance environment: \(environment)"
    case .processFailed(let message): "conformance process failed: \(message)"
    }
  }
}
