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
      if !matchesWithinEdgeEnvelope(
        solid.pixels[index],
        x: x,
        y: y,
        channel: channel,
        reference: reference,
        radius: tolerance.edgeRadius,
        channelTolerance: tolerance.maximumInteriorChannelDifference
      ) {
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
