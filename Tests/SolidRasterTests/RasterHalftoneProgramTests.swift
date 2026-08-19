import Testing

@testable import SolidRaster

@Suite struct RasterHalftoneProgramTests {
  @Test func thresholdScreenUsesAbsoluteWrappedCoordinates() throws {
    let screen = try RasterThresholdScreen(
      width: 2,
      height: 2,
      maximumThreshold: 4,
      thresholds: [0, 2, 3, 4]
    )

    #expect(screen.thresholds == [1, 2, 3, 4])
    #expect(screen.threshold(x: 0, y: 0) == 0.25)
    #expect(screen.threshold(x: -1, y: -1) == 1)
    #expect(screen.threshold(x: 2, y: 2) == 0.25)
  }

  @Test func programValidatesTransferAndQuantizationTables() throws {
    #expect(throws: RasterError.invalidGeometry) {
      try RasterHalftoneProgram(redTransfer: [0], componentLevels: [2])
    }
    #expect(throws: RasterError.invalidGeometry) {
      try RasterHalftoneProgram(componentLevels: [1])
    }
    #expect(RasterHalftoneProgram.continuousTone.defaultScreen == nil)
  }
}
