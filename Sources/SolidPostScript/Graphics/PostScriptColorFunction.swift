import Foundation
import SolidColor

extension Operators {
  static func parseColorFunction(
    _ object: Object,
    context: isolated Context,
    depth: Int = 0
  ) async throws -> ColorFunction {
    guard depth < 32 else { throw Error.limitCheck }
    let dictionary = try object.value(as: DictionaryValue.self)
    let functionType = try dictionary.objectValue(forKey: "FunctionType", as: IntegerValue.self).value
    let domain = try componentRanges(try numericArray(dictionary.object(forKey: "Domain")))
    let range = try dictionary.object(forKeyIfExists: "Range").map {
      try componentRanges(try numericArray($0))
    }
    do {
      switch functionType {
      case 0:
        guard let range else { throw Error.undefined }
        let size = try numericArray(dictionary.object(forKey: "Size")).map {
          guard $0.rounded() == $0, $0 > 0, $0 <= Double(Int.max) else { throw Error.rangeCheck }
          return Int($0)
        }
        let bits = Int(try dictionary.objectValue(forKey: "BitsPerSample", as: IntegerValue.self).value)
        let order = Int(try dictionary.objectValue(forKeyIfExists: "Order", as: IntegerValue.self)?.value ?? 1)
        let encode = try dictionary.object(forKeyIfExists: "Encode").map(numericArray)
        let decode = try dictionary.object(forKeyIfExists: "Decode").map(numericArray)
        let scalarCount = try sampledScalarCount(size: size, outputCount: range.count)
        let byteCount = try sampledByteCount(scalars: scalarCount, bits: bits)
        let dataSource = try dictionary.object(forKey: "DataSource")
        let data = try await functionData(
          dataSource,
          byteCount: byteCount,
          context: context
        )
        return .sampled(try ColorSampledFunction(
          domain: domain,
          range: range,
          size: size,
          bitsPerSample: bits,
          order: order,
          encode: encode,
          decode: decode,
          sampleData: data
        ))
      case 2:
        guard domain.count == 1 else { throw Error.rangeCheck }
        let c0 = try dictionary.object(forKeyIfExists: "C0").map(numericArray) ?? [0]
        let c1 = try dictionary.object(forKeyIfExists: "C1").map(numericArray) ?? [1]
        let exponent = try numeric(dictionary.object(forKey: "N"))
        return .exponential(try ColorExponentialFunction(
          domain: domain[0],
          range: range,
          c0: c0,
          c1: c1,
          exponent: exponent
        ))
      case 3:
        guard domain.count == 1 else { throw Error.rangeCheck }
        let functionObjects = try arrayObjects(dictionary.object(forKey: "Functions"))
        var functions: [ColorFunction] = []
        functions.reserveCapacity(functionObjects.count)
        for function in functionObjects {
          functions.append(try await parseColorFunction(function, context: context, depth: depth + 1))
        }
        let bounds = try numericArray(dictionary.object(forKey: "Bounds"))
        let encode = try numericArray(dictionary.object(forKey: "Encode"))
        return .stitching(try ColorStitchingFunction(
          domain: domain[0],
          range: range,
          functions: functions,
          bounds: bounds,
          encode: encode
        ))
      default:
        throw Error.rangeCheck
      }
    } catch let error as Error {
      throw error
    } catch ColorError.tableSize {
      throw Error.limitCheck
    } catch {
      throw Error.rangeCheck
    }
  }

  static func numericArray(_ object: Object) throws -> [Double] {
    try arrayObjects(object).map(numeric)
  }

  private static func sampledScalarCount(size: [Int], outputCount: Int) throws -> Int {
    var count = outputCount
    for value in size {
      let product = count.multipliedReportingOverflow(by: value)
      guard !product.overflow, product.partialValue <= 16_000_000 else { throw Error.limitCheck }
      count = product.partialValue
    }
    return count
  }

  private static func sampledByteCount(scalars: Int, bits: Int) throws -> Int {
    guard [1, 2, 4, 8, 12, 16, 24, 32].contains(bits) else { throw Error.rangeCheck }
    let bitCount = scalars.multipliedReportingOverflow(by: bits)
    guard !bitCount.overflow else { throw Error.limitCheck }
    return (bitCount.partialValue + 7) / 8
  }

  private static func functionData(
    _ object: Object,
    byteCount: Int,
    context: isolated Context
  ) async throws -> Data {
    if let string = object.value as? StringValue {
      try string.access.check(.read)
      let bytes = try string.characters(in: string.range)
      guard bytes.count >= byteCount else { throw Error.rangeCheck }
      return Data(bytes.prefix(byteCount))
    }
    let file = try object.value(as: FileValue.self)
    try file.checkReadable()
    guard file.file.isPositionable else { throw Error.invalidAccess }
    try context.setLogicalOffset(0, in: file.file)
    var data = Data(capacity: byteCount)
    while data.count < byteCount {
      guard let chunk = try await context.read(max: byteCount - data.count, from: file.file),
        !chunk.isEmpty
      else { throw Error.rangeCheck }
      data.append(chunk)
    }
    return data
  }
}
