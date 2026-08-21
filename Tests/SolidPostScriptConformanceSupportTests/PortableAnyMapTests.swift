import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct PortableAnyMapTests {
  @Test func decodesPGMWithComments() throws {
    var data = Data("P5\n# fixture\n2 1\n255\n".utf8)
    data.append(contentsOf: [0, 255])

    let raster = try PortableAnyMap.decode(data, maximumPixels: 2)

    #expect(raster.width == 2)
    #expect(raster.channels == 1)
    #expect(raster.pixels == Data([0, 255]))
  }

  @Test func decodesPAM() throws {
    var data = Data("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n".utf8)
    data.append(contentsOf: [1, 2, 3, 4])

    let raster = try PortableAnyMap.decode(data, maximumPixels: 1)

    #expect(raster.channels == 4)
    #expect(raster.pixels == Data([1, 2, 3, 4]))
  }

  @Test func roundTripsRawGrayAndRGB() throws {
    for channels in [1, 3] {
      let raster = try PortableRaster(
        width: 2,
        height: 1,
        channels: channels,
        pixels: Data((0..<(2 * channels)).map(UInt8.init))
      )
      let decoded = try PortableAnyMap.decode(PortableAnyMap.encode(raster), maximumPixels: 2)
      #expect(decoded == raster)
    }
  }

  @Test func createsDeterministicDifferenceImage() throws {
    let solid = try PortableRaster(width: 1, height: 1, channels: 3, pixels: Data([10, 20, 30]))
    let reference = try PortableRaster(width: 1, height: 1, channels: 3, pixels: Data([12, 90, 28]))

    let difference = try ConformanceRasterComparator.differenceImage(solid, reference)

    #expect(difference.pixels == Data([70, 0, 0]))
  }

  @Test func rejectsTruncatedRaster() {
    #expect(throws: ConformanceError.self) {
      try PortableAnyMap.decode(Data("P6\n1 1\n255\n\u{00}\u{00}".utf8), maximumPixels: 1)
    }
  }

  @Test func permitsOnePixelEdgeDisplacement() throws {
    let solid = try PortableRaster(width: 3, height: 1, channels: 1, pixels: Data([0, 255, 0]))
    let reference = try PortableRaster(width: 3, height: 1, channels: 1, pixels: Data([255, 0, 0]))

    let difference = try ConformanceRasterComparator.compare(
      solid,
      reference,
      tolerance: ConformanceRasterTolerance(
        maximumInteriorChannelDifference: 4,
        edgeRadius: 1,
        maximumRMSE: 255
      )
    )

    #expect(difference.isEquivalent)
  }

  @Test func rejectsInteriorColorChanges() throws {
    let solid = try PortableRaster(width: 1, height: 1, channels: 3, pixels: Data([0, 0, 0]))
    let reference = try PortableRaster(width: 1, height: 1, channels: 3, pixels: Data([20, 0, 0]))

    let difference = try ConformanceRasterComparator.compare(
      solid,
      reference,
      tolerance: .default
    )

    #expect(!difference.isEquivalent)
  }
}
