import Foundation
import Testing

@testable import SolidRaster

@Suite
struct RasterColorantCanvasTests {
  @Test func knockoutClearsUnspecifiedColorantsAndOverprintPreservesThem() throws {
    let path = RasterPath(elements: [
      .move(to: RasterPoint(x: 0, y: 0)),
      .line(to: RasterPoint(x: 2, y: 0)),
      .line(to: RasterPoint(x: 2, y: 1)),
      .line(to: RasterPoint(x: 0, y: 1)),
      .close,
    ])
    var canvas = try RasterColorantCanvas(width: 2, height: 1, colorants: ["Cyan", "Spot"])
    try canvas.fill(path, rule: .winding, paint: RasterColorantPaint(tints: ["Spot": 1]))
    try canvas.fill(
      path,
      rule: .winding,
      paint: RasterColorantPaint(tints: ["Cyan": 0.5], overprintsUnspecifiedColorants: true)
    )
    let planes = try canvas.finish()

    #expect(Array(planes[0].mask.data) == [128, 128])
    #expect(Array(planes[1].mask.data) == [255, 255])
  }

  @Test func nonePaintLeavesEveryPlaneUnchanged() throws {
    let path = RasterPath(elements: [
      .move(to: RasterPoint(x: 0, y: 0)),
      .line(to: RasterPoint(x: 1, y: 0)),
      .line(to: RasterPoint(x: 1, y: 1)),
      .line(to: RasterPoint(x: 0, y: 1)),
      .close,
    ])
    var canvas = try RasterColorantCanvas(width: 1, height: 1, colorants: ["Black"])
    try canvas.fill(
      path,
      rule: .winding,
      paint: RasterColorantPaint(tints: [:], paintsNothing: true)
    )
    #expect(Array(try canvas.finish()[0].mask.data) == [0])
  }

  @Test func disabledTrappingLeavesSeparatedOutputUnchanged() throws {
    let left = rectangle(x: 0, y: 0, width: 10, height: 10)
    let right = rectangle(x: 10, y: 0, width: 10, height: 10)
    var reference = try RasterColorantCanvas(width: 20, height: 10, colorants: ["Cyan", "Magenta"])
    try reference.fill(left, rule: .winding, paint: RasterColorantPaint(tints: ["Cyan": 1]))
    try reference.fill(right, rule: .winding, paint: RasterColorantPaint(tints: ["Magenta": 1]))

    var disabled = try RasterColorantCanvas(width: 20, height: 10, colorants: ["Cyan", "Magenta"])
    try disabled.configureTrapping(.disabled)
    try disabled.fill(left, rule: .winding, paint: RasterColorantPaint(tints: ["Cyan": 1]))
    try disabled.fill(right, rule: .winding, paint: RasterColorantPaint(tints: ["Magenta": 1]))

    #expect(try reference.finish() == disabled.finish())
  }

  @Test func trappingAddsInkOnlyWithinTheNewestZoneAndConfiguredWidth() throws {
    let left = rectangle(x: 0, y: 0, width: 10, height: 10)
    let right = rectangle(x: 10, y: 0, width: 10, height: 10)
    let zone = rectangle(x: 0, y: 0, width: 20, height: 5)
    let program = RasterTrappingProgram(
      enabled: true,
      width: 2,
      stepLimit: 0.5,
      colorScaling: 1,
      blackDensityLimit: 1,
      blackColorLimit: 0.5,
      blackWidth: 1,
      slidingLimit: 1,
      trapsImagesToObjects: false,
      trapsInsideImages: false,
      neutralDensities: ["Cyan": 0.7, "Magenta": 0.7],
      zones: [RasterTrappingZone(path: zone, stepLimit: 0.5, colorScaling: 1, width: 2)]
    )
    var canvas = try RasterColorantCanvas(width: 20, height: 10, colorants: ["Cyan", "Magenta"])
    try canvas.configureTrapping(program)
    try canvas.fill(left, rule: .winding, paint: RasterColorantPaint(tints: ["Cyan": 1]))
    try canvas.fill(right, rule: .winding, paint: RasterColorantPaint(tints: ["Magenta": 1]))
    let planes = try canvas.finish()
    let cyan = planes[0].mask.data

    #expect(cyan[4 * 20 + 10] == 255)
    #expect(cyan[4 * 20 + 12] == 255)
    #expect(cyan[4 * 20 + 13] == 0)
    #expect(cyan[7 * 20 + 10] == 0)
  }

  @Test func colorantZoneOverridesAndTransparentInksControlTrapEligibility() throws {
    let left = rectangle(x: 0, y: 0, width: 2, height: 1)
    let right = rectangle(x: 2, y: 0, width: 2, height: 1)
    let zone = rectangle(x: 0, y: 0, width: 4, height: 1)
    let suppressedCyan = RasterTrappingProgram(
      enabled: true,
      width: 1,
      stepLimit: 0.5,
      colorScaling: 1,
      blackDensityLimit: 1,
      blackColorLimit: 0.5,
      blackWidth: 1,
      slidingLimit: 1,
      trapsImagesToObjects: false,
      trapsInsideImages: false,
      neutralDensities: ["Cyan": 0.7, "Magenta": 0.7],
      zones: [RasterTrappingZone(
        path: zone,
        stepLimit: 0.5,
        colorScaling: 1,
        width: 1,
        colorantColorScales: ["Cyan": 0]
      )]
    )
    var scaledCanvas = try RasterColorantCanvas(width: 4, height: 1, colorants: ["Cyan", "Magenta"])
    try scaledCanvas.configureTrapping(suppressedCyan)
    try scaledCanvas.fill(left, rule: .winding, paint: RasterColorantPaint(tints: ["Cyan": 1]))
    try scaledCanvas.fill(right, rule: .winding, paint: RasterColorantPaint(tints: ["Magenta": 1]))
    #expect(try scaledCanvas.finish()[0].mask.data[2] == 0)

    let transparentCyan = RasterTrappingProgram(
      enabled: true,
      width: 1,
      stepLimit: 0.5,
      colorScaling: 1,
      blackDensityLimit: 1,
      blackColorLimit: 0.5,
      blackWidth: 1,
      slidingLimit: 1,
      trapsImagesToObjects: false,
      trapsInsideImages: false,
      neutralDensities: ["Cyan": 0.7, "Magenta": 0.7],
      colorantBehaviors: ["Cyan": .transparent],
      zones: [RasterTrappingZone(path: zone, stepLimit: 0.5, colorScaling: 1, width: 1)]
    )
    var transparentCanvas = try RasterColorantCanvas(
      width: 4,
      height: 1,
      colorants: ["Cyan", "Magenta"]
    )
    try transparentCanvas.configureTrapping(transparentCyan)
    try transparentCanvas.fill(left, rule: .winding, paint: RasterColorantPaint(tints: ["Cyan": 1]))
    try transparentCanvas.fill(right, rule: .winding, paint: RasterColorantPaint(tints: ["Magenta": 1]))
    #expect(try transparentCanvas.finish()[0].mask.data[2] == 0)
  }

  @Test func imageInternalTrappingAnalyzesColorChangesWithoutChangingImageOwnership() throws {
    let zone = rectangle(x: 0, y: 0, width: 2, height: 1)
    let program = RasterTrappingProgram(
      enabled: true,
      width: 1,
      stepLimit: 0.5,
      colorScaling: 1,
      blackDensityLimit: 1,
      blackColorLimit: 0.5,
      blackWidth: 1,
      slidingLimit: 1,
      trapsImagesToObjects: false,
      trapsInsideImages: true,
      neutralDensities: ["Cyan": 0.7, "Magenta": 0.7],
      zones: [RasterTrappingZone(path: zone, stepLimit: 0.5, colorScaling: 1, width: 1)]
    )
    let cyan = RasterColorantPlane(
      name: "Cyan",
      mask: try RasterMask(width: 2, height: 1, bytesPerRow: 2, data: Data([255, 0]))
    )
    let magenta = RasterColorantPlane(
      name: "Magenta",
      mask: try RasterMask(width: 2, height: 1, bytesPerRow: 2, data: Data([0, 255]))
    )
    var canvas = try RasterColorantCanvas(width: 2, height: 1, colorants: ["Cyan", "Magenta"])
    try canvas.configureTrapping(program)
    try canvas.draw([cyan, magenta], transform: .identity)
    let planes = try canvas.finish()

    #expect(planes[0].mask.data[1] == 255)
    #expect(planes[1].mask.data[0] == 0)
  }

  private func rectangle(x: Double, y: Double, width: Double, height: Double) -> RasterPath {
    RasterPath(elements: [
      .move(to: RasterPoint(x: x, y: y)),
      .line(to: RasterPoint(x: x + width, y: y)),
      .line(to: RasterPoint(x: x + width, y: y + height)),
      .line(to: RasterPoint(x: x, y: y + height)),
      .close,
    ])
  }
}
