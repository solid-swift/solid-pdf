import Foundation

/// An immutable sampled color function corresponding to PostScript FunctionType 0.
public struct ColorSampledFunction: Sendable, Hashable {
  /// Inclusive input ranges, one for each input component.
  public let domain: [ColorComponentRange]
  /// Optional inclusive output ranges.
  public let range: [ColorComponentRange]?
  /// Sample counts for each input dimension.
  public let size: [Int]
  /// Bits used by each high-bit-first sample.
  public let bitsPerSample: Int
  /// Interpolation order, either linear (`1`) or cubic (`3`).
  public let order: Int
  /// Encoded coordinate ranges, one pair per input.
  public let encode: [Double]
  /// Decoded output ranges, one pair per output.
  public let decode: [Double]
  /// Normalized sample values in PostScript dimension order.
  public let samples: [Double]

  /// The number of function inputs.
  public var inputCount: Int { domain.count }
  /// The number of function outputs.
  public var outputCount: Int { decode.count / 2 }

  /// Creates and validates a sampled function from packed high-bit-first sample data.
  public init(
    domain: [ColorComponentRange],
    range: [ColorComponentRange]? = nil,
    size: [Int],
    bitsPerSample: Int,
    order: Int = 1,
    encode: [Double]? = nil,
    decode: [Double]? = nil,
    sampleData: Data
  ) throws(ColorError) {
    guard (1...8).contains(domain.count), size.count == domain.count,
      domain.allSatisfy({ $0.lowerBound <= $0.upperBound }), size.allSatisfy({ $0 > 0 }),
      [1, 2, 4, 8, 12, 16, 24, 32].contains(bitsPerSample), order == 1 || order == 3
    else { throw .invalidDomain }
    let encode: [Double] = encode ?? size.flatMap { [0.0, Double($0 - 1)] }
    guard encode.count == domain.count * 2, encode.allSatisfy(\.isFinite) else {
      throw .componentCount
    }
    let outputCount = range?.count ?? ((decode?.count ?? 0) / 2)
    guard (1...16).contains(outputCount) else { throw .componentCount }
    let decode = decode ?? range!.flatMap { [$0.lowerBound, $0.upperBound] }
    guard decode.count == outputCount * 2, decode.allSatisfy(\.isFinite),
      range == nil || range?.count == outputCount
    else { throw .componentCount }

    var scalarCount = outputCount
    for dimension in size {
      let product = scalarCount.multipliedReportingOverflow(by: dimension)
      guard !product.overflow, product.partialValue <= 16_000_000 else { throw .tableSize }
      scalarCount = product.partialValue
    }
    let bitCount = scalarCount.multipliedReportingOverflow(by: bitsPerSample)
    guard !bitCount.overflow else { throw .tableSize }
    let byteCount = (bitCount.partialValue + 7) / 8
    guard byteCount <= 64 * 1_024 * 1_024, sampleData.count >= byteCount else { throw .tableSize }

    let maximum = bitsPerSample == 32 ? Double(UInt32.max) : Double((UInt64(1) << bitsPerSample) - 1)
    let bytes = [UInt8](sampleData.prefix(byteCount))
    var reader = BitReader(bytes: bytes)
    var samples: [Double] = []
    samples.reserveCapacity(scalarCount)
    for _ in 0..<scalarCount {
      guard let value = reader.read(bits: bitsPerSample) else { throw .tableSize }
      samples.append(Double(value) / maximum)
    }

    self.domain = domain
    self.range = range
    self.size = size
    self.bitsPerSample = bitsPerSample
    self.order = order
    self.encode = encode
    self.decode = decode
    self.samples = samples
  }

  /// Evaluates the sampled function.
  public func evaluate(_ input: [Double]) throws(ColorError) -> [Double] {
    guard input.count == inputCount, input.allSatisfy(\.isFinite) else { throw .componentCount }
    let positions = input.indices.map { axis -> Double in
      let clipped = domain[axis].clamp(input[axis])
      let width = domain[axis].upperBound - domain[axis].lowerBound
      let fraction = width == 0 ? 0 : (clipped - domain[axis].lowerBound) / width
      let encoded = encode[axis * 2] + fraction * (encode[axis * 2 + 1] - encode[axis * 2])
      return min(Double(size[axis] - 1), max(0, encoded))
    }
    var result = Array(repeating: 0.0, count: outputCount)
    if order == 3, size.allSatisfy({ $0 >= 4 }) {
      interpolateCubic(positions, into: &result)
    } else {
      interpolateLinear(positions, into: &result)
    }
    for component in result.indices {
      let decoded = decode[component * 2]
        + result[component] * (decode[component * 2 + 1] - decode[component * 2])
      result[component] = range?[component].clamp(decoded) ?? decoded
    }
    return result
  }

  private func interpolateLinear(_ positions: [Double], into result: inout [Double]) {
    let corners = 1 << positions.count
    for corner in 0..<corners {
      var coordinate = Array(repeating: 0, count: positions.count)
      var weight = 1.0
      for axis in positions.indices {
        let lower = Int(positions[axis].rounded(.down))
        let upper = min(size[axis] - 1, lower + 1)
        let fraction = positions[axis] - Double(lower)
        if corner & (1 << axis) == 0 {
          coordinate[axis] = lower
          weight *= 1 - fraction
        } else {
          coordinate[axis] = upper
          weight *= fraction
        }
      }
      accumulate(coordinate: coordinate, weight: weight, into: &result)
    }
  }

  private func interpolateCubic(_ positions: [Double], into result: inout [Double]) {
    var coordinates = Array(repeating: 0, count: positions.count)
    func visit(_ axis: Int, _ weight: Double) {
      if axis == positions.count {
        accumulate(coordinate: coordinates, weight: weight, into: &result)
        return
      }
      let floor = Int(positions[axis].rounded(.down))
      let fraction = positions[axis] - Double(floor)
      let weights = cubicWeights(fraction)
      for offset in 0..<4 {
        coordinates[axis] = min(size[axis] - 1, max(0, floor + offset - 1))
        visit(axis + 1, weight * weights[offset])
      }
    }
    visit(0, 1)
  }

  private func accumulate(coordinate: [Int], weight: Double, into result: inout [Double]) {
    var index = 0
    var stride = 1
    for axis in coordinate.indices {
      index += coordinate[axis] * stride
      stride *= size[axis]
    }
    let offset = index * outputCount
    for component in result.indices {
      result[component] += samples[offset + component] * weight
    }
  }

  private func cubicWeights(_ value: Double) -> [Double] {
    let value2 = value * value
    let value3 = value2 * value
    return [
      -0.5 * value3 + value2 - 0.5 * value,
      1.5 * value3 - 2.5 * value2 + 1,
      -1.5 * value3 + 2 * value2 + 0.5 * value,
      0.5 * value3 - 0.5 * value2,
    ]
  }
}

private struct BitReader {
  let bytes: [UInt8]
  var bitOffset = 0

  mutating func read(bits: Int) -> UInt64? {
    guard bitOffset + bits <= bytes.count * 8 else { return nil }
    var value: UInt64 = 0
    for _ in 0..<bits {
      let byte = bytes[bitOffset / 8]
      value = (value << 1) | UInt64((byte >> (7 - bitOffset % 8)) & 1)
      bitOffset += 1
    }
    return value
  }
}
