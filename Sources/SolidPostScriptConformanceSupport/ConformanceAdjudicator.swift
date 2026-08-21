import Foundation

package enum ConformanceAdjudicator {
  package static func evaluate(
    _ testCase: ConformanceCaseManifest,
    suite: ConformanceSuite,
    solid: ConformanceObservationResult,
    reference: ConformanceObservationResult? = nil,
    referenceVersion: String? = nil,
    durationMilliseconds: Int = 0,
    additionalDifferences: [String] = []
  ) throws -> ConformanceCaseResult {
    let solidExpected = testCase.expectation?.solid
    let referenceExpected = testCase.expectation?.reference
    var differences = try compare(solid, expected: solidExpected, suite: suite, testCase: testCase, label: "Solid")
    differences += additionalDifferences

    switch testCase.disposition {
    case .equivalent:
      guard let reference else {
        return ConformanceCaseResult(
          id: testCase.id,
          status: differences.isEmpty ? .passed : .failed,
          durationMilliseconds: durationMilliseconds,
          solid: solid,
          differences: differences
        )
      }
      differences += compare(
        solid,
        actual: reference,
        label: "reference",
        compareRasterDigests: !testCase.observations.contains(.raster)
      )
    case .solidExpected:
      break
    case .acceptedDifference:
      guard let reference else { break }
      guard referenceVersion == testCase.expectation?.referenceVersion else {
        differences.append("accepted reference version is stale or unavailable")
        return ConformanceCaseResult(
          id: testCase.id,
          status: .difference,
          durationMilliseconds: durationMilliseconds,
          solid: solid,
          reference: reference,
          differences: differences
        )
      }
      differences += try compare(
        reference,
        expected: referenceExpected,
        suite: suite,
        testCase: testCase,
        label: "reference"
      )
    case .discovery:
      if let reference {
        differences += compare(
          solid,
          actual: reference,
          label: "reference",
          compareRasterDigests: !testCase.observations.contains(.raster)
        )
      }
      return ConformanceCaseResult(
        id: testCase.id,
        status: differences.isEmpty ? .passed : .difference,
        durationMilliseconds: durationMilliseconds,
        solid: solid,
        reference: reference,
        differences: differences
      )
    }
    return ConformanceCaseResult(
      id: testCase.id,
      status: differences.isEmpty ? .passed : .failed,
      durationMilliseconds: durationMilliseconds,
      solid: solid,
      reference: reference,
      differences: differences
    )
  }

  private static func compare(
    _ actual: ConformanceObservationResult,
    expected: ConformanceExpectedResult?,
    suite: ConformanceSuite,
    testCase: ConformanceCaseManifest,
    label: String
  ) throws -> [String] {
    guard let expected else { return [] }
    var differences: [String] = []
    if expected.transcript != nil {
      guard let transcript = actual.transcript else {
        differences.append("\(label) transcript is missing")
        return differences
      }
      let expectedData = try suite.expectedTranscript(path: expected.transcript!)
      let lhs = try ConformanceTranscript.parse(transcript, maximumBytes: testCase.limits.maximumTranscriptBytes)
      let rhs = try ConformanceTranscript.parse(expectedData, maximumBytes: testCase.limits.maximumTranscriptBytes)
      if !lhs.isEquivalent(to: rhs) { differences.append("\(label) transcript differs") }
    }
    if let digest = expected.recordingDigest, actual.recordingDigest != digest {
      differences.append("\(label) recording digest differs")
    }
    if !expected.rasterDigests.isEmpty, actual.rasterDigests != expected.rasterDigests {
      differences.append("\(label) raster digest differs")
    }
    return differences
  }

  private static func compare(
    _ solid: ConformanceObservationResult,
    actual reference: ConformanceObservationResult,
    label: String,
    compareRasterDigests: Bool
  ) -> [String] {
    var differences: [String] = []
    if let lhsData = solid.transcript, let rhsData = reference.transcript,
      let lhs = try? ConformanceTranscript.parse(lhsData, maximumBytes: max(lhsData.count, 1)),
      let rhs = try? ConformanceTranscript.parse(rhsData, maximumBytes: max(rhsData.count, 1)),
      !lhs.isEquivalent(to: rhs)
    {
      differences.append("Solid transcript differs from \(label)")
    } else if (solid.transcript == nil) != (reference.transcript == nil) {
      differences.append("Solid and \(label) transcript availability differs")
    }
    if solid.recordingDigest != reference.recordingDigest {
      differences.append("Solid recording differs from \(label)")
    }
    if compareRasterDigests, solid.rasterDigests != reference.rasterDigests {
      differences.append("Solid raster differs from \(label)")
    }
    return differences
  }
}
