import Foundation
import SolidIO
import SolidRaster

/// A deterministic, noninterlaced PNG encoder for `RasterImage` values.
public struct PNGEncoder: Sendable {
  private static let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
  private static let idatChunkSize = 64 * 1_024

  public let options: PNGEncodingOptions

  /// Creates an encoder.
  public init(options: PNGEncodingOptions = .init()) throws {
    guard (-1...9).contains(options.compressionLevel),
      options.resolutionDPI.map({ $0.isFinite && $0 > 0 }) ?? true
    else { throw PNGEncodingError.invalidOptions }
    self.options = options
  }

  /// Encodes an image in memory.
  public func encode(_ image: RasterImage) throws -> Data {
    var output = Data()
    try encode(image) { output.append($0) }
    return output
  }

  /// Atomically encodes an image to a file URL.
  public func encode(_ image: RasterImage, to url: URL, replacingExisting: Bool = false) throws {
    let manager = FileManager.default
    if manager.fileExists(atPath: url.path), !replacingExisting { throw PNGEncodingError.outputExists }
    let directory = url.deletingLastPathComponent()
    let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    guard manager.createFile(atPath: temporary.path, contents: nil) else { throw PNGEncodingError.outputFailure }
    do {
      let handle = try FileHandle(forWritingTo: temporary)
      do {
        try encode(image) { try handle.write(contentsOf: $0) }
        try handle.synchronize()
        try handle.close()
      } catch {
        try? handle.close()
        throw error
      }
      if manager.fileExists(atPath: url.path) {
        _ = try manager.replaceItemAt(url, withItemAt: temporary)
      } else {
        try manager.moveItem(at: temporary, to: url)
      }
    } catch let error as PNGEncodingError {
      try? manager.removeItem(at: temporary)
      throw error
    } catch {
      try? manager.removeItem(at: temporary)
      throw PNGEncodingError.outputFailure
    }
  }

  private func encode(_ image: RasterImage, write: (Data) throws -> Void) throws {
    guard image.width > 0, image.height > 0,
      image.width <= Int(UInt32.max), image.height <= Int(UInt32.max)
    else { throw PNGEncodingError.invalidImage }
    try write(Self.signature)
    let colorType: UInt8 = options.colorFormat == .rgb ? 2 : 6
    var header = Data()
    header.appendBigEndian(UInt32(image.width))
    header.appendBigEndian(UInt32(image.height))
    header.append(contentsOf: [8, colorType, 0, 0, 0])
    try write(Self.chunk(type: "IHDR", payload: header))
    try write(Self.chunk(type: "sRGB", payload: Data([0])))
    if let dpi = options.resolutionDPI {
      let pixelsPerMeter = UInt32(clamping: Int((dpi / 0.0254).rounded()))
      var physical = Data()
      physical.appendBigEndian(pixelsPerMeter)
      physical.appendBigEndian(pixelsPerMeter)
      physical.append(1)
      try write(Self.chunk(type: "pHYs", payload: physical))
    }

    let compressor: ZlibStreamEncoder
    do { compressor = try ZlibStreamEncoder(compressionLevel: options.compressionLevel) }
    catch { throw PNGEncodingError.compressionFailure }
    let components = colorType == 2 ? 3 : 4
    var previous = [UInt8](repeating: 0, count: image.width * components)
    var pending = Data()
    for row in 0..<image.height {
      let current = try convertedRow(image, row: row, components: components)
      let filtered = filteredRow(current, previous: previous, components: components)
      do { pending.append(try compressor.process(filtered)) }
      catch { throw PNGEncodingError.compressionFailure }
      try drainIDAT(&pending, write: write)
      previous = current
    }
    do { pending.append(try compressor.finish() ?? Data()) }
    catch { throw PNGEncodingError.compressionFailure }
    while !pending.isEmpty {
      let count = min(Self.idatChunkSize, pending.count)
      try write(Self.chunk(type: "IDAT", payload: pending.prefix(count)))
      pending.removeFirst(count)
    }
    try write(Self.chunk(type: "IEND", payload: Data()))
  }

  private func convertedRow(_ image: RasterImage, row: Int, components: Int) throws -> [UInt8] {
    var result = [UInt8]()
    result.reserveCapacity(image.width * components)
    let start = row * image.bytesPerRow
    guard start >= 0, start + image.width * 4 <= image.data.count else { throw PNGEncodingError.invalidImage }
    for column in 0..<image.width {
      let offset = start + column * 4
      let alpha = image.data[offset + 3]
      var red = image.data[offset]
      var green = image.data[offset + 1]
      var blue = image.data[offset + 2]
      if image.pixelFormat == .rgba8UnormPremultiplied, alpha != 0, alpha != 255 {
        red = UInt8(clamping: (Int(red) * 255 + Int(alpha) / 2) / Int(alpha))
        green = UInt8(clamping: (Int(green) * 255 + Int(alpha) / 2) / Int(alpha))
        blue = UInt8(clamping: (Int(blue) * 255 + Int(alpha) / 2) / Int(alpha))
      } else if image.pixelFormat == .rgba8UnormPremultiplied, alpha == 0 {
        red = 0; green = 0; blue = 0
      }
      if components == 3 {
        result.append(Self.flatten(red, alpha: alpha, background: options.background.red))
        result.append(Self.flatten(green, alpha: alpha, background: options.background.green))
        result.append(Self.flatten(blue, alpha: alpha, background: options.background.blue))
      } else {
        result.append(contentsOf: [red, green, blue, alpha])
      }
    }
    return result
  }

  private func filteredRow(_ row: [UInt8], previous: [UInt8], components: Int) -> Data {
    let candidates = switch options.filterStrategy {
    case .adaptive: PNGFilter.allCases
    case .fixed(let filter): [filter]
    }
    var selected: (score: UInt64, bytes: [UInt8], filter: PNGFilter)?
    for filter in candidates {
      let bytes = Self.apply(filter, row: row, previous: previous, components: components)
      let score = bytes.reduce(UInt64(0)) { total, byte in
        total + UInt64(min(Int(byte), 256 - Int(byte)))
      }
      if selected == nil || score < selected!.score { selected = (score, bytes, filter) }
    }
    let chosen = selected!
    return Data([Self.identifier(chosen.filter)] + chosen.bytes)
  }

  private func drainIDAT(_ pending: inout Data, write: (Data) throws -> Void) throws {
    while pending.count >= Self.idatChunkSize {
      try write(Self.chunk(type: "IDAT", payload: pending.prefix(Self.idatChunkSize)))
      pending.removeFirst(Self.idatChunkSize)
    }
  }

  private static func apply(
    _ filter: PNGFilter,
    row: [UInt8],
    previous: [UInt8],
    components: Int
  ) -> [UInt8] {
    row.indices.map { index in
      let left = index >= components ? row[index - components] : 0
      let up = previous[index]
      let upperLeft = index >= components ? previous[index - components] : 0
      let predictor: UInt8 = switch filter {
      case .none: 0
      case .sub: left
      case .up: up
      case .average: UInt8((Int(left) + Int(up)) / 2)
      case .paeth: paeth(left, up, upperLeft)
      }
      return row[index] &- predictor
    }
  }

  private static func paeth(_ left: UInt8, _ up: UInt8, _ upperLeft: UInt8) -> UInt8 {
    let prediction = Int(left) + Int(up) - Int(upperLeft)
    let leftDistance = abs(prediction - Int(left))
    let upDistance = abs(prediction - Int(up))
    let diagonalDistance = abs(prediction - Int(upperLeft))
    if leftDistance <= upDistance, leftDistance <= diagonalDistance { return left }
    if upDistance <= diagonalDistance { return up }
    return upperLeft
  }

  private static func identifier(_ filter: PNGFilter) -> UInt8 {
    switch filter { case .none: 0; case .sub: 1; case .up: 2; case .average: 3; case .paeth: 4 }
  }

  private static func flatten(_ value: UInt8, alpha: UInt8, background: UInt8) -> UInt8 {
    let opacity = Int(alpha)
    let source = Int(value) * opacity
    let backdrop = Int(background) * (255 - opacity)
    return UInt8((source + backdrop + 127) / 255)
  }

  private static func chunk(type: String, payload: some DataProtocol) -> Data {
    let typeData = Data(type.utf8)
    let payload = Data(payload)
    var result = Data()
    result.appendBigEndian(UInt32(payload.count))
    result.append(typeData)
    result.append(payload)
    result.appendBigEndian(crc32(typeData + payload))
    return result
  }

  private static func crc32(_ data: Data) -> UInt32 {
    var crc = UInt32.max
    for byte in data {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB8_8320) }
    }
    return crc ^ UInt32.max
  }
}

private extension Data {
  mutating func appendBigEndian(_ value: UInt32) {
    append(contentsOf: [
      UInt8(truncatingIfNeeded: value >> 24),
      UInt8(truncatingIfNeeded: value >> 16),
      UInt8(truncatingIfNeeded: value >> 8),
      UInt8(truncatingIfNeeded: value),
    ])
  }
}
