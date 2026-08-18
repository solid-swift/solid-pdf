/// A bounded multidimensional table with multilinear interpolation.
public struct ColorLookupTable: Sendable, Hashable {
  /// Sample counts for each input dimension.
  public let dimensions: [Int]
  /// Number of components stored at every sample point.
  public let outputComponentCount: Int
  /// Interleaved table values in row-major dimension order.
  public let values: [Double]

  /// Creates and validates a lookup table with at most four input dimensions.
  public init(dimensions: [Int], outputComponentCount: Int, values: [Double]) throws(ColorError) {
    guard (1...4).contains(dimensions.count), dimensions.allSatisfy({ $0 >= 2 }),
      outputComponentCount > 0, outputComponentCount <= 16,
      values.allSatisfy(\.isFinite)
    else { throw .invalidValue }
    var count = outputComponentCount
    for dimension in dimensions {
      let result = count.multipliedReportingOverflow(by: dimension)
      guard !result.overflow, result.partialValue <= 16 * 1_024 * 1_024 else { throw .tableSize }
      count = result.partialValue
    }
    guard values.count == count else { throw .componentCount }
    self.dimensions = dimensions
    self.outputComponentCount = outputComponentCount
    self.values = values
  }

  /// Interpolates one output vector for normalized input components.
  public func interpolate(_ input: [Double]) throws(ColorError) -> [Double] {
    guard input.count == dimensions.count, input.allSatisfy(\.isFinite) else { throw .componentCount }
    var result = Array(repeating: 0.0, count: outputComponentCount)
    let cornerCount = 1 << dimensions.count
    for corner in 0..<cornerCount {
      var weight = 1.0
      var tableIndex = 0
      for axis in dimensions.indices {
        let position = input[axis].clampedUnit * Double(dimensions[axis] - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(dimensions[axis] - 1, lower + 1)
        let fraction = position - Double(lower)
        let high = corner & (1 << axis) != 0
        let coordinate = high ? upper : lower
        weight *= high ? fraction : 1 - fraction
        tableIndex = tableIndex * dimensions[axis] + coordinate
      }
      let offset = tableIndex * outputComponentCount
      for component in result.indices {
        result[component] += values[offset + component] * weight
      }
    }
    return result
  }
}
