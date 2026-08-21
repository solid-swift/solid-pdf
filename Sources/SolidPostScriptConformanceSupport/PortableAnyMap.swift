import Foundation

package struct PortableRaster: Sendable, Hashable {
  package let width: Int
  package let height: Int
  package let channels: Int
  package let pixels: Data

  package init(width: Int, height: Int, channels: Int, pixels: Data) throws {
    let count = width.multipliedReportingOverflow(by: height)
    let bytes = count.partialValue.multipliedReportingOverflow(by: channels)
    guard width > 0, height > 0, channels > 0, !count.overflow, !bytes.overflow, pixels.count == bytes.partialValue else {
      throw ConformanceError.processFailed("invalid portable raster dimensions")
    }
    self.width = width
    self.height = height
    self.channels = channels
    self.pixels = pixels
  }

  package var digest: String {
    var value = Data("pnm-v1 \(width) \(height) \(channels)\n".utf8)
    value.append(pixels)
    return ConformanceDigest.sha256(value)
  }
}

package enum PortableAnyMap {
  package static func encode(_ raster: PortableRaster) throws -> Data {
    guard raster.channels == 1 || raster.channels == 3 else {
      throw ConformanceError.processFailed("only gray and RGB portable rasters can be encoded")
    }
    let magic = raster.channels == 1 ? "P5" : "P6"
    var data = Data("\(magic)\n\(raster.width) \(raster.height)\n255\n".utf8)
    data.append(raster.pixels)
    return data
  }

  package static func decode(_ data: Data, maximumPixels: Int) throws -> PortableRaster {
    var parser = Parser(data: data)
    let magic = try parser.token()
    switch magic {
    case "P5", "P6":
      let width = try parser.positiveInteger()
      let height = try parser.positiveInteger()
      let maximum = try parser.positiveInteger()
      guard maximum == 255 else { throw ConformanceError.processFailed("unsupported PNM maximum value") }
      try parser.consumeRasterSeparator()
      return try raster(
        width: width,
        height: height,
        channels: magic == "P5" ? 1 : 3,
        bytes: data[parser.offset...],
        maximumPixels: maximumPixels
      )
    case "P7":
      var width: Int?
      var height: Int?
      var depth: Int?
      var maximum: Int?
      while true {
        let key = try parser.token()
        if key == "ENDHDR" { break }
        if key == "TUPLTYPE" {
          _ = try parser.token()
          continue
        }
        let value = try parser.positiveInteger()
        switch key {
        case "WIDTH": width = value
        case "HEIGHT": height = value
        case "DEPTH": depth = value
        case "MAXVAL": maximum = value
        default: throw ConformanceError.processFailed("unsupported PAM header field \(key)")
        }
      }
      try parser.consumeRasterSeparator()
      guard let width, let height, let depth, maximum == 255, (1...4).contains(depth) else {
        throw ConformanceError.processFailed("invalid PAM header")
      }
      return try raster(
        width: width,
        height: height,
        channels: depth,
        bytes: data[parser.offset...],
        maximumPixels: maximumPixels
      )
    default:
      throw ConformanceError.processFailed("unsupported portable anymap magic")
    }
  }

  private static func raster(
    width: Int,
    height: Int,
    channels: Int,
    bytes: Data.SubSequence,
    maximumPixels: Int
  ) throws -> PortableRaster {
    let pixels = width.multipliedReportingOverflow(by: height)
    let count = pixels.partialValue.multipliedReportingOverflow(by: channels)
    guard !pixels.overflow, pixels.partialValue <= maximumPixels, !count.overflow, bytes.count == count.partialValue else {
      throw ConformanceError.rasterLimitExceeded
    }
    return try PortableRaster(width: width, height: height, channels: channels, pixels: Data(bytes))
  }

  private struct Parser {
    let data: Data
    var offset = 0

    mutating func token() throws -> String {
      skipWhitespaceAndComments()
      let start = offset
      while offset < data.count, !Self.isWhitespace(data[offset]), data[offset] != 0x23 { offset += 1 }
      guard offset > start, let value = String(data: data[start..<offset], encoding: .ascii) else {
        throw ConformanceError.processFailed("truncated portable anymap header")
      }
      return value
    }

    mutating func positiveInteger() throws -> Int {
      guard let value = Int(try token()), value > 0 else {
        throw ConformanceError.processFailed("invalid portable anymap integer")
      }
      return value
    }

    mutating func consumeRasterSeparator() throws {
      guard offset < data.count, Self.isWhitespace(data[offset]) else {
        throw ConformanceError.processFailed("portable anymap header lacks raster separator")
      }
      if data[offset] == 0x0D, offset + 1 < data.count, data[offset + 1] == 0x0A { offset += 2 } else { offset += 1 }
    }

    mutating func skipWhitespaceAndComments() {
      while offset < data.count {
        if Self.isWhitespace(data[offset]) {
          offset += 1
        } else if data[offset] == 0x23 {
          while offset < data.count, data[offset] != 0x0A, data[offset] != 0x0D { offset += 1 }
        } else {
          return
        }
      }
    }

    static func isWhitespace(_ byte: UInt8) -> Bool {
      byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
    }
  }
}
