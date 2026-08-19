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
    #expect(throws: RasterError.invalidGeometry) {
      try RasterHalftoneProgram(colorantLevels: ["Varnish": 1])
    }
    #expect(throws: RasterError.invalidGeometry) {
      try RasterHalftoneProgram(colorantTransfers: ["Varnish": [0]])
    }
    #expect(RasterHalftoneProgram.continuousTone.defaultScreen == nil)
  }

  @Test func namedColorantsUseIndependentTransfersLevelsAndScreens() throws {
    let screen = try RasterThresholdScreen(
      width: 2,
      height: 1,
      maximumThreshold: 4,
      thresholds: [1, 3]
    )
    let program = try RasterHalftoneProgram(
      colorantLevels: ["Varnish": 2],
      defaultColorantLevels: 4,
      colorantScreens: ["Varnish": screen],
      colorantTransfers: ["Varnish": [1, 0]]
    )

    #expect(program.quantizeTint(1, colorant: "Varnish", x: 0, y: 0) == 0)
    #expect(program.quantizeTint(0, colorant: "Varnish", x: 0, y: 0) == 1)
    #expect(program.quantizeTint(1, colorant: "Cyan", x: 0, y: 0) == 1)
    #expect(program.quantizeTint(0, colorant: "Cyan", x: 0, y: 0) == 0)
  }
}
