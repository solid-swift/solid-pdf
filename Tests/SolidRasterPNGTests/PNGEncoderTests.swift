import Foundation
import SolidRaster
import SolidRasterPNG
import Testing

@Suite
struct PNGEncoderTests {
  @Test
  func emitsDeterministicPNGStructureAndResolution() throws {
    let image = try RasterImage(
      width: 2,
      height: 1,
      bytesPerRow: 8,
      pixelFormat: .rgba8Unorm,
      data: Data([255, 0, 0, 255, 0, 255, 0, 128])
    )
    let encoder = try PNGEncoder(options: .init(colorFormat: .rgba, resolutionDPI: 144))
    let first = try encoder.encode(image)
    let second = try encoder.encode(image)
    #expect(first == second)
    #expect(first.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]))
    #expect(chunkTypes(first) == ["IHDR", "sRGB", "pHYs", "IDAT", "IEND"])
  }

  @Test(arguments: PNGFilter.allCases)
  func supportsEveryFilter(_ filter: PNGFilter) throws {
    let image = try RasterImage(
      width: 1,
      height: 2,
      bytesPerRow: 4,
      pixelFormat: .rgba8UnormPremultiplied,
      data: Data([64, 32, 16, 128, 0, 0, 0, 0])
    )
    let encoded = try PNGEncoder(options: .init(filterStrategy: .fixed(filter))).encode(image)
    #expect(encoded.count > 40)
  }

  @Test
  func atomicOutputDoesNotReplaceWithoutPermission() throws {
    let image = try RasterImage(
      width: 1,
      height: 1,
      bytesPerRow: 4,
      pixelFormat: .rgba8Unorm,
      data: Data([0, 0, 0, 255])
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("test.png")
    try Data("existing".utf8).write(to: output)
    let encoder = try PNGEncoder()
    #expect(throws: PNGEncodingError.outputExists) { try encoder.encode(image, to: output) }
    #expect(try Data(contentsOf: output) == Data("existing".utf8))
  }
}

private func chunkTypes(_ data: Data) -> [String] {
  var offset = 8
  var result: [String] = []
  while offset + 12 <= data.count {
    let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
    let type = String(data: data[offset + 4..<offset + 8], encoding: .ascii)!
    result.append(type)
    offset += 12 + length
  }
  return result
}
