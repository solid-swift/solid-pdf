import Foundation

package struct ConformanceSuiteManifest: Codable, Sendable, Hashable {
  package let schemaVersion: Int
  package let name: String
  package let cases: [ConformanceCaseManifest]

  package init(schemaVersion: Int = 1, name: String, cases: [ConformanceCaseManifest]) {
    self.schemaVersion = schemaVersion
    self.name = name
    self.cases = cases
  }
}

package struct ConformanceCaseManifest: Codable, Sendable, Hashable {
  package let id: String
  package let title: String
  package let authority: [ConformanceAuthority]
  package let tags: [String]
  package let mode: ConformanceCaseMode
  package let source: String
  package let environment: ConformanceEnvironment
  package let observations: [ConformanceObservation]
  package let limits: ConformanceLimits
  package let disposition: ConformanceDisposition
  package let expectation: ConformanceExpectation?
  package let rasterTolerance: ConformanceRasterTolerance

  package init(
    id: String,
    title: String,
    authority: [ConformanceAuthority],
    tags: [String] = [],
    mode: ConformanceCaseMode = .wrapped,
    source: String,
    environment: ConformanceEnvironment = .portable,
    observations: [ConformanceObservation] = [.transcript],
    limits: ConformanceLimits = .default,
    disposition: ConformanceDisposition,
    expectation: ConformanceExpectation? = nil,
    rasterTolerance: ConformanceRasterTolerance = .default
  ) {
    self.id = id
    self.title = title
    self.authority = authority
    self.tags = tags
    self.mode = mode
    self.source = source
    self.environment = environment
    self.observations = observations
    self.limits = limits
    self.disposition = disposition
    self.expectation = expectation
    self.rasterTolerance = rasterTolerance
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, authority, tags, mode, source, environment, observations, limits, disposition, expectation
    case rasterTolerance
  }

  package init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    title = try values.decode(String.self, forKey: .title)
    authority = try values.decode([ConformanceAuthority].self, forKey: .authority)
    tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
    mode = try values.decodeIfPresent(ConformanceCaseMode.self, forKey: .mode) ?? .wrapped
    source = try values.decode(String.self, forKey: .source)
    environment = try values.decodeIfPresent(ConformanceEnvironment.self, forKey: .environment) ?? .portable
    observations = try values.decodeIfPresent([ConformanceObservation].self, forKey: .observations) ?? [.transcript]
    limits = try values.decodeIfPresent(ConformanceLimits.self, forKey: .limits) ?? .default
    disposition = try values.decode(ConformanceDisposition.self, forKey: .disposition)
    expectation = try values.decodeIfPresent(ConformanceExpectation.self, forKey: .expectation)
    rasterTolerance = try values.decodeIfPresent(ConformanceRasterTolerance.self, forKey: .rasterTolerance) ?? .default
  }
}

package struct ConformanceAuthority: Codable, Sendable, Hashable {
  package let document: String
  package let section: String
  package let note: String?

  package init(document: String = "PLRM3", section: String, note: String? = nil) {
    self.document = document
    self.section = section
    self.note = note
  }
}

package enum ConformanceCaseMode: String, Codable, Sendable, Hashable {
  case wrapped
  case raw
  case document
}

package enum ConformanceEnvironment: String, Codable, Sendable, Hashable {
  case portable
  case coreText
  case freeType
  case separation
  case printSpool
}

package enum ConformanceObservation: String, Codable, Sendable, Hashable {
  case transcript
  case recording
  case raster
  case separation
  case printSpool
}

package enum ConformanceDisposition: String, Codable, Sendable, Hashable {
  case equivalent
  case solidExpected
  case acceptedDifference
  case discovery
}

package struct ConformanceExpectation: Codable, Sendable, Hashable {
  package let solid: ConformanceExpectedResult?
  package let reference: ConformanceExpectedResult?
  package let referenceVersion: String?
  package let rationale: String?

  package init(
    solid: ConformanceExpectedResult? = nil,
    reference: ConformanceExpectedResult? = nil,
    referenceVersion: String? = nil,
    rationale: String? = nil
  ) {
    self.solid = solid
    self.reference = reference
    self.referenceVersion = referenceVersion
    self.rationale = rationale
  }
}

package struct ConformanceExpectedResult: Codable, Sendable, Hashable {
  package let transcript: String?
  package let recordingDigest: String?
  package let rasterDigests: [String]

  package init(transcript: String? = nil, recordingDigest: String? = nil, rasterDigests: [String] = []) {
    self.transcript = transcript
    self.recordingDigest = recordingDigest
    self.rasterDigests = rasterDigests
  }

  private enum CodingKeys: String, CodingKey {
    case transcript, recordingDigest, rasterDigests
  }

  package init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    transcript = try values.decodeIfPresent(String.self, forKey: .transcript)
    recordingDigest = try values.decodeIfPresent(String.self, forKey: .recordingDigest)
    rasterDigests = try values.decodeIfPresent([String].self, forKey: .rasterDigests) ?? []
  }
}

package struct ConformanceLimits: Codable, Sendable, Hashable {
  package static let `default` = Self()

  package let timeoutMilliseconds: Int
  package let maximumInputBytes: Int
  package let maximumTranscriptBytes: Int
  package let maximumRasterPixels: Int
  package let maximumTemporaryBytes: Int

  package init(
    timeoutMilliseconds: Int = 10_000,
    maximumInputBytes: Int = 64 * 1_024 * 1_024,
    maximumTranscriptBytes: Int = 1 * 1_024 * 1_024,
    maximumRasterPixels: Int = 128_000_000,
    maximumTemporaryBytes: Int = 512 * 1_024 * 1_024
  ) {
    self.timeoutMilliseconds = timeoutMilliseconds
    self.maximumInputBytes = maximumInputBytes
    self.maximumTranscriptBytes = maximumTranscriptBytes
    self.maximumRasterPixels = maximumRasterPixels
    self.maximumTemporaryBytes = maximumTemporaryBytes
  }
}

package struct ConformanceRasterTolerance: Codable, Sendable, Hashable {
  package static let `default` = Self()

  package let maximumInteriorChannelDifference: UInt8
  package let edgeRadius: Int
  package let maximumRMSE: Double
  package let rationale: String?

  package init(
    maximumInteriorChannelDifference: UInt8 = 4,
    edgeRadius: Int = 1,
    maximumRMSE: Double = 3,
    rationale: String? = nil
  ) {
    self.maximumInteriorChannelDifference = maximumInteriorChannelDifference
    self.edgeRadius = edgeRadius
    self.maximumRMSE = maximumRMSE
    self.rationale = rationale
  }
}
