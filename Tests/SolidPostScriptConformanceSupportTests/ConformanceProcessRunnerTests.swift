import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceProcessRunnerTests {
  @Test func capturesBoundedOutput() throws {
    let result = try ConformanceProcessRunner.run(
      executable: URL(fileURLWithPath: "/bin/echo"),
      arguments: ["conformance"],
      timeoutMilliseconds: 1_000,
      maximumOutputBytes: 100
    )

    #expect(result.terminationStatus == 0)
    #expect(result.standardOutput == Data("conformance\n".utf8))
    #expect(!result.timedOut)
  }

  @Test func terminatesTimedOutWorkers() throws {
    let result = try ConformanceProcessRunner.run(
      executable: URL(fileURLWithPath: "/bin/sleep"),
      arguments: ["2"],
      timeoutMilliseconds: 20,
      maximumOutputBytes: 100
    )

    #expect(result.timedOut)
  }
}
