import Foundation

package struct ConformanceRasterDifference: Codable, Sendable, Hashable {
  package let maximumChannelDifference: UInt8
  package let normalizedRMSE: Double
  package let structuralFailureCount: Int

  package var isEquivalent: Bool { structuralFailureCount == 0 }
}

package enum ConformanceRasterComparator {
  package static func compare(
    _ solid: PortableRaster,
    _ reference: PortableRaster,
    tolerance: ConformanceRasterTolerance
  ) throws -> ConformanceRasterDifference {
    guard solid.width == reference.width, solid.height == reference.height, solid.channels == reference.channels else {
      throw ConformanceError.processFailed("raster page dimensions or channels differ")
    }
    var maximum: UInt8 = 0
    var squaredError = 0.0
    var failures = 0
    let count = solid.pixels.count
    for index in 0..<count {
      let difference = UInt8(abs(Int(solid.pixels[index]) - Int(reference.pixels[index])))
      maximum = max(maximum, difference)
      squaredError += Double(difference) * Double(difference)
      guard difference > tolerance.maximumInteriorChannelDifference else { continue }
      let pixel = index / solid.channels
      let x = pixel % solid.width
      let y = pixel / solid.width
      let channel = index % solid.channels
      let isEdge = hasEdge(
        atX: x,
        y: y,
        channel: channel,
        raster: solid,
        radius: tolerance.edgeRadius,
        channelTolerance: tolerance.maximumInteriorChannelDifference
      ) || hasEdge(
        atX: x,
        y: y,
        channel: channel,
        raster: reference,
        radius: tolerance.edgeRadius,
        channelTolerance: tolerance.maximumInteriorChannelDifference
      )
      let isSymmetricMatch = matchesWithinEdgeEnvelope(
        solid.pixels[index],
        x: x,
        y: y,
        channel: channel,
        reference: reference,
        radius: tolerance.edgeRadius,
        channelTolerance: tolerance.maximumInteriorChannelDifference
      ) && matchesWithinEdgeEnvelope(
        reference.pixels[index],
        x: x,
        y: y,
        channel: channel,
        reference: solid,
        radius: tolerance.edgeRadius,
        channelTolerance: tolerance.maximumInteriorChannelDifference
      )
      if !isEdge || !isSymmetricMatch {
        failures += 1
      }
    }
    let rmse = count == 0 ? 0 : sqrt(squaredError / Double(count))
    if rmse > tolerance.maximumRMSE { failures += 1 }
    return ConformanceRasterDifference(
      maximumChannelDifference: maximum,
      normalizedRMSE: rmse,
      structuralFailureCount: failures
    )
  }

  private static func hasEdge(
    atX x: Int,
    y: Int,
    channel: Int,
    raster: PortableRaster,
    radius: Int,
    channelTolerance: UInt8
  ) -> Bool {
    let center = raster.pixels[(y * raster.width + x) * raster.channels + channel]
    for candidateY in max(0, y - radius)...min(raster.height - 1, y + radius) {
      for candidateX in max(0, x - radius)...min(raster.width - 1, x + radius) {
        let index = (candidateY * raster.width + candidateX) * raster.channels + channel
        if abs(Int(center) - Int(raster.pixels[index])) > Int(channelTolerance) { return true }
      }
    }
    return false
  }

  package static func differenceImage(_ solid: PortableRaster, _ reference: PortableRaster) throws -> PortableRaster {
    guard solid.width == reference.width, solid.height == reference.height, solid.channels == reference.channels else {
      throw ConformanceError.processFailed("raster page dimensions or channels differ")
    }
    let pixelCount = solid.width.multipliedReportingOverflow(by: solid.height)
    let byteCount = pixelCount.partialValue.multipliedReportingOverflow(by: 3)
    guard !pixelCount.overflow, !byteCount.overflow else { throw ConformanceError.rasterLimitExceeded }
    var pixels = Data(capacity: byteCount.partialValue)
    for pixel in 0..<pixelCount.partialValue {
      var difference = 0
      for channel in 0..<solid.channels {
        let index = pixel * solid.channels + channel
        difference = max(difference, abs(Int(solid.pixels[index]) - Int(reference.pixels[index])))
      }
      pixels.append(UInt8(clamping: difference))
      pixels.append(0)
      pixels.append(0)
    }
    return try PortableRaster(width: solid.width, height: solid.height, channels: 3, pixels: pixels)
  }

  private static func matchesWithinEdgeEnvelope(
    _ value: UInt8,
    x: Int,
    y: Int,
    channel: Int,
    reference: PortableRaster,
    radius: Int,
    channelTolerance: UInt8
  ) -> Bool {
    for candidateY in max(0, y - radius)...min(reference.height - 1, y + radius) {
      for candidateX in max(0, x - radius)...min(reference.width - 1, x + radius) {
        let index = (candidateY * reference.width + candidateX) * reference.channels + channel
        if abs(Int(value) - Int(reference.pixels[index])) <= Int(channelTolerance) { return true }
      }
    }
    return false
  }
}
