import Foundation
import SolidPDF
import SolidPostScript

extension PDFGraphicsResourceResolver {
  func halftone(
    _ object: PDFObject,
    device: GraphicsDeviceDescriptor,
    maximumBytes: Int
  ) async throws -> GraphicsHalftone {
    var active: Set<PDFObjectReference> = []
    return try await halftone(
      object,
      device: device,
      maximumBytes: maximumBytes,
      depth: 0,
      active: &active
    )
  }

  private func halftone(
    _ object: PDFObject,
    device: GraphicsDeviceDescriptor,
    maximumBytes: Int,
    depth: Int,
    active: inout Set<PDFObjectReference>
  ) async throws -> GraphicsHalftone {
    guard depth < 64 else { throw PDFObjectAccess.TypeMismatch.dictionary }
    let resolved = try await halftoneObject(object, active: &active)
    defer {
      if let reference = resolved.reference { active.remove(reference) }
    }
    let dictionary = resolved.dictionary
    if let typeName = dictionary["Type"] {
      guard try PDFObjectAccess.name(typeName).pdfGraphicsString == "Halftone" else {
        throw PDFObjectAccess.TypeMismatch.dictionary
      }
    }
    guard let typeObject = dictionary["HalftoneType"] else {
      guard dictionary["HalftoneName"] != nil else { throw PDFObjectAccess.TypeMismatch.dictionary }
      return .default
    }
    let type = try PDFObjectAccess.integer(typeObject)
    switch type {
    case 1:
      return .spot(try await spotScreen(
        dictionary,
        device: device,
        maximumBytes: maximumBytes
      ))
    case 5:
      var screens: [String: GraphicsHalftone] = [:]
      let standardColorants: Set<String> = [
        "Gray", "Red", "Green", "Blue", "Cyan", "Magenta", "Yellow", "Black",
      ]
      let hasNonprimary = dictionary.keys.contains {
        let key = $0.pdfGraphicsString
        return key != "Type" && key != "HalftoneType" && key != "HalftoneName"
          && key != "Default" && !standardColorants.contains(key)
      }
      for (name, child) in dictionary {
        let key = name.pdfGraphicsString
        guard key != "Type", key != "HalftoneType", key != "HalftoneName" else { continue }
        if (!standardColorants.contains(key) && key != "Default") || (key == "Default" && hasNonprimary) {
          guard try await hasTransferFunction(child) else { throw PDFObjectAccess.TypeMismatch.dictionary }
        }
        let screen = try await halftone(
          child,
          device: device,
          maximumBytes: maximumBytes,
          depth: depth + 1,
          active: &active
        )
        if case .colorants = screen { throw PDFObjectAccess.TypeMismatch.dictionary }
        screens[key] = screen
      }
      guard screens["Default"] != nil else { throw PDFObjectAccess.TypeMismatch.dictionary }
      return .colorants(screens)
    case 6:
      guard let data = resolved.data else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let width = try positiveInteger(dictionary["Width"])
      let height = try positiveInteger(dictionary["Height"])
      let count = try checkedProduct(width, height, maximum: maximumBytes)
      guard data.count == count else { throw PDFObjectAccess.TypeMismatch.array }
      return .threshold(try GraphicsThresholdScreen(
        width: width,
        height: height,
        thresholds: data.map(UInt16.init),
        transferFunction: try await transferFunction(dictionary)
      ))
    case 10:
      guard let data = resolved.data else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let x = try positiveInteger(dictionary["Xsquare"])
      let y = try positiveInteger(dictionary["Ysquare"])
      let first = try checkedProduct(x, x, maximum: maximumBytes)
      let second = try checkedProduct(y, y, maximum: maximumBytes)
      let count = try checkedSum(first, second, maximum: maximumBytes)
      guard data.count == count else { throw PDFObjectAccess.TypeMismatch.array }
      return .threshold(try GraphicsThresholdScreen(
        width: x,
        height: x,
        thresholds: data.map(UInt16.init),
        secondaryWidth: y,
        secondaryHeight: y,
        usesAngledSquares: true,
        transferFunction: try await transferFunction(dictionary)
      ))
    case 16:
      guard let data = resolved.data else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let width = try positiveInteger(dictionary["Width"])
      let height = try positiveInteger(dictionary["Height"])
      let width2 = try dictionary["Width2"].map(positiveInteger)
      let height2 = try dictionary["Height2"].map(positiveInteger)
      guard (width2 == nil) == (height2 == nil) else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let first = try checkedProduct(width, height, maximum: maximumBytes / 2)
      let second = try width2.map {
        try checkedProduct($0, height2!, maximum: maximumBytes / 2)
      } ?? 0
      let count = try checkedSum(first, second, maximum: maximumBytes / 2)
      guard data.count == count * 2 else { throw PDFObjectAccess.TypeMismatch.array }
      var thresholds: [UInt16] = []
      thresholds.reserveCapacity(count)
      for offset in stride(from: 0, to: data.count, by: 2) {
        thresholds.append(UInt16(data[offset]) << 8 | UInt16(data[offset + 1]))
      }
      return .threshold(try GraphicsThresholdScreen(
        width: width,
        height: height,
        bitsPerSample: 16,
        thresholds: thresholds,
        secondaryWidth: width2,
        secondaryHeight: height2,
        transferFunction: try await transferFunction(dictionary)
      ))
    default:
      throw PDFObjectAccess.TypeMismatch.integer
    }
  }

  private func spotScreen(
    _ dictionary: [PDFName: PDFObject],
    device: GraphicsDeviceDescriptor,
    maximumBytes: Int
  ) async throws -> GraphicsSpotScreen {
    let frequency = try PDFObjectAccess.number(dictionary["Frequency"] ?? .null)
    let angle = try PDFObjectAccess.number(dictionary["Angle"] ?? .null)
    guard frequency > 0, frequency.isFinite, angle.isFinite else {
      throw PDFObjectAccess.TypeMismatch.number
    }
    if let accurate = dictionary["AccurateScreens"] {
      guard case .boolean = accurate else { throw PDFObjectAccess.TypeMismatch.dictionary }
    }
    let resolution = min(device.horizontalResolution, device.verticalResolution)
    let requestedSide = (resolution / frequency).rounded()
    guard requestedSide.isFinite, requestedSide <= Double(Int.max) else {
      throw PDFGraphicsError.limitExceeded("PDF spot screen exceeds interpretation scratch.", location: nil)
    }
    let side = max(1, Int(requestedSide))
    let count = try checkedProduct(side, side, maximum: maximumBytes / MemoryLayout<UInt16>.stride)
    let evaluate = try await spotFunction(dictionary["SpotFunction"] ?? .null)
    var samples: [(value: Double, index: Int)] = []
    samples.reserveCapacity(count)
    for row in 0..<side {
      for column in 0..<side {
        let x = (Double(column) + 0.5) * 2 / Double(side) - 1
        let y = (Double(row) + 0.5) * 2 / Double(side) - 1
        let value = try evaluate(x, y)
        guard value.isFinite, value >= -1, value <= 1 else {
          throw PDFObjectAccess.TypeMismatch.number
        }
        samples.append((value, row * side + column))
      }
    }
    samples.sort { $0.value == $1.value ? $0.index < $1.index : $0.value < $1.value }
    var thresholds = Array(repeating: UInt16(1), count: count)
    for (rank, sample) in samples.enumerated() {
      thresholds[sample.index] = UInt16(max(1, (rank + 1) * Int(UInt16.max) / count))
    }
    return try GraphicsSpotScreen(
      frequency: frequency,
      angle: angle,
      actualFrequency: resolution / Double(side),
      actualAngle: angle.truncatingRemainder(dividingBy: 360),
      width: side,
      height: side,
      thresholds: thresholds,
      transferFunction: try await transferFunction(dictionary)
    )
  }

  private func spotFunction(
    _ object: PDFObject
  ) async throws -> @Sendable (Double, Double) throws -> Double {
    if case .name(let name) = object {
      guard let function = Self.predefinedSpotFunction(name.pdfGraphicsString) else {
        throw PDFObjectAccess.TypeMismatch.name
      }
      return function
    }
    let function = try await colorFunction(object)
    guard function.inputCount == 2, function.outputCount == 1 else {
      throw PDFObjectAccess.TypeMismatch.array
    }
    return { try function.evaluate([$0, $1])[0] }
  }

  private func transferFunction(
    _ dictionary: [PDFName: PDFObject]
  ) async throws -> GraphicsComponentFunction? {
    guard let object = dictionary["TransferFunction"] else { return nil }
    return try await componentFunction(object)
  }

  private func halftoneObject(
    _ object: PDFObject,
    active: inout Set<PDFObjectReference>
  ) async throws -> (dictionary: [PDFName: PDFObject], data: Data?, reference: PDFObjectReference?) {
    switch object {
    case .dictionary(let dictionary):
      return (dictionary, nil, nil)
    case .reference(let reference):
      guard active.insert(reference).inserted else { throw PDFObjectAccess.TypeMismatch.dictionary }
      do {
        switch try await document.resolve(reference, in: revision).value {
        case .value(.dictionary(let dictionary)):
          return (dictionary, nil, reference)
        case .stream(let stream):
          return (stream.dictionary, try await document.decodedBytes(of: stream), reference)
        default:
          active.remove(reference)
          throw PDFObjectAccess.TypeMismatch.dictionary
        }
      } catch {
        active.remove(reference)
        throw error
      }
    default:
      throw PDFObjectAccess.TypeMismatch.dictionary
    }
  }

  private func hasTransferFunction(_ object: PDFObject) async throws -> Bool {
    switch object {
    case .dictionary(let dictionary):
      return dictionary["TransferFunction"] != nil
    case .reference(let reference):
      switch try await document.resolve(reference, in: revision).value {
      case .value(.dictionary(let dictionary)): return dictionary["TransferFunction"] != nil
      case .stream(let stream): return stream.dictionary["TransferFunction"] != nil
      default: throw PDFObjectAccess.TypeMismatch.dictionary
      }
    default:
      throw PDFObjectAccess.TypeMismatch.dictionary
    }
  }

  private func positiveInteger(_ object: PDFObject?) throws -> Int {
    let value = try PDFObjectAccess.integer(object ?? .null)
    guard value > 0 else { throw PDFObjectAccess.TypeMismatch.integer }
    return value
  }

  private func checkedProduct(_ first: Int, _ second: Int, maximum: Int) throws -> Int {
    let result = first.multipliedReportingOverflow(by: second)
    guard !result.overflow, result.partialValue <= maximum else {
      throw PDFGraphicsError.limitExceeded("PDF halftone storage exceeds interpretation scratch.", location: nil)
    }
    return result.partialValue
  }

  private func checkedSum(_ first: Int, _ second: Int, maximum: Int) throws -> Int {
    let result = first.addingReportingOverflow(second)
    guard !result.overflow, result.partialValue <= maximum else {
      throw PDFGraphicsError.limitExceeded("PDF halftone storage exceeds interpretation scratch.", location: nil)
    }
    return result.partialValue
  }

  private static func predefinedSpotFunction(
    _ name: String
  ) -> (@Sendable (Double, Double) -> Double)? {
    switch name {
    case "SimpleDot": { 1 - ($0 * $0 + $1 * $1) }
    case "InvertedSimpleDot": { $0 * $0 + $1 * $1 - 1 }
    case "DoubleDot": { (sin(2 * .pi * $0) + sin(2 * .pi * $1)) / 2 }
    case "InvertedDoubleDot": { -(sin(2 * .pi * $0) + sin(2 * .pi * $1)) / 2 }
    case "CosineDot": { (cos(.pi * $0) + cos(.pi * $1)) / 2 }
    case "Double": { (sin(.pi * $0) + sin(2 * .pi * $1)) / 2 }
    case "InvertedDouble": { -(sin(.pi * $0) + sin(2 * .pi * $1)) / 2 }
    case "Line": { _, y in -abs(y) }
    case "LineX": { x, _ in x }
    case "LineY": { _, y in y }
    case "Round": { roundSpot(x: $0, y: $1) }
    case "Ellipse": { ellipseSpot(x: $0, y: $1) }
    case "EllipseA": { 1 - ($0 * $0 + 0.9 * $1 * $1) }
    case "InvertedEllipseA": { $0 * $0 + 0.9 * $1 * $1 - 1 }
    case "EllipseB": { 1 - sqrt($0 * $0 + 0.625 * $1 * $1) }
    case "EllipseC": { 1 - (0.9 * $0 * $0 + $1 * $1) }
    case "InvertedEllipseC": { 0.9 * $0 * $0 + $1 * $1 - 1 }
    case "Square": { -max(abs($0), abs($1)) }
    case "Cross": { -min(abs($0), abs($1)) }
    case "Rhomboid": { (0.9 * abs($0) + abs($1)) / 2 }
    case "Diamond": { diamondSpot(x: $0, y: $1) }
    default: nil
    }
  }

  private static func roundSpot(x: Double, y: Double) -> Double {
    let x = abs(x)
    let y = abs(y)
    if x + y <= 1 { return 1 - (x * x + y * y) }
    return (x - 1) * (x - 1) + (y - 1) * (y - 1) - 1
  }

  private static func ellipseSpot(x: Double, y: Double) -> Double {
    let x = abs(x)
    let y = abs(y)
    let weight = 3 * x + 4 * y - 3
    if weight < 0 { return 1 - (x * x + (y / 0.75) * (y / 0.75)) / 4 }
    if weight > 1 {
      return ((1 - x) * (1 - x) + ((1 - y) / 0.75) * ((1 - y) / 0.75)) / 4 - 1
    }
    return 0.5 - weight
  }

  private static func diamondSpot(x: Double, y: Double) -> Double {
    let x = abs(x)
    let y = abs(y)
    if x + y <= 0.75 { return 1 - (x * x + y * y) }
    if x + y <= 1.23 { return 1 - (0.85 * x + y) }
    return (x - 1) * (x - 1) + (y - 1) * (y - 1) - 1
  }
}
