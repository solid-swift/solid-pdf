import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceTranscriptTests {
  @Test func parsesEveryProbeValue() throws {
    let transcript = Data("""
      SPS-CONFORMANCE 1
      V 6e null -
      V 62 boolean true
      V 69 integer -42
      V 72 real 0.5
      V 6e6d name 412f42
      V 73 string 00ff
      V 61 array 3
      """.utf8)

    let parsed = try ConformanceTranscript.parse(transcript, maximumBytes: 1_024)

    #expect(parsed.records.count == 7)
  }

  @Test func comparesNumericValuesSemantically() throws {
    let left = try ConformanceTranscript.parse(
      Data("SPS-CONFORMANCE 1\nV 72 real 0.5\n".utf8),
      maximumBytes: 100
    )
    let right = try ConformanceTranscript.parse(
      Data("SPS-CONFORMANCE 1\nV 72 real 0.5000000001\n".utf8),
      maximumBytes: 100
    )

    #expect(left.isEquivalent(to: right))
  }

  @Test func rejectsMalformedHex() {
    #expect(throws: ConformanceError.self) {
      try ConformanceTranscript.parse(Data("SPS-CONFORMANCE 1\nV zz string 00\n".utf8), maximumBytes: 100)
    }
  }
}
