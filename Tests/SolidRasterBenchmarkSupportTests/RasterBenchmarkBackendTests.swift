import SolidRasterBenchmarkSupport
import Testing

@Suite struct RasterBenchmarkBackendTests {
  @Test func backendSelectionDefaultsAndParsesKnownNames() throws {
    #expect(try RasterBenchmarkBackend(environmentValue: nil) == .native)
    #expect(try RasterBenchmarkBackend(environmentValue: "") == .native)
    #expect(try RasterBenchmarkBackend(environmentValue: "native") == .native)
    #expect(try RasterBenchmarkBackend(environmentValue: "PLUTOVG") == .plutovg)
  }

  @Test func unknownBackendFailsBeforeRegistration() {
    #expect(throws: RasterBenchmarkBackend.SelectionError.unknownBackend("metal")) {
      try RasterBenchmarkBackend(environmentValue: "metal")
    }
  }

  @Test func comparisonExitStatusesAreClassified() {
    #expect(RasterBenchmarkCheckOutcome(exitStatus: 0) == .withinTolerance)
    #expect(RasterBenchmarkCheckOutcome(exitStatus: 2) == .regression)
    #expect(RasterBenchmarkCheckOutcome(exitStatus: 4) == .improvement)
    #expect(RasterBenchmarkCheckOutcome(exitStatus: 1) == .infrastructureFailure(1))
    #expect(
      RasterBenchmarkCheckOutcome(
        processExitStatus: 1,
        diagnosticOutput: "error: benchmarkThresholdRegression"
      ) == .regression
    )
    #expect(
      RasterBenchmarkCheckOutcome(processExitStatus: 1, diagnosticOutput: "plugin crashed")
        == .infrastructureFailure(1)
    )
    #expect(RasterBenchmarkCheckOutcome(exitStatus: 0).passed)
    #expect(RasterBenchmarkCheckOutcome(exitStatus: 4).passed)
    #expect(!RasterBenchmarkCheckOutcome(exitStatus: 2).passed)
  }
}
