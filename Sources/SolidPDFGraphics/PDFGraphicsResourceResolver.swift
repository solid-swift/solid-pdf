import Foundation
import SolidColor
import SolidPDF
import SolidPostScript

final class PDFGraphicsResourceResolver<Source: PDFInputSource> {
  struct ResolvedColorSpace {
    let description: GraphicsColorSpaceDescription
    let realization: GraphicsColorSpaceRealization?
    let initialComponents: [Double]
    let makePaint: @Sendable ([Double]) throws -> GraphicsPaint
    var underlyingMakePaint: (@Sendable ([Double]) throws -> GraphicsPaint)? = nil
  }

  let document: PDFDocument<Source>
  let revision: PDFRevisionIdentifier
  private let limits: PDFGraphicsLimits
  private var scopes: [[PDFName: PDFObject]]
  private var colorSpaceCache: [PDFName: ResolvedColorSpace] = [:]
  private var activeReusableResources: Set<PDFObjectReference> = []
  private var diagnosedICCProfiles: Set<PDFObjectReference> = []
  private(set) var diagnostics: [PDFGraphicsDiagnostic] = []

  init(
    document: PDFDocument<Source>,
    revision: PDFRevisionIdentifier,
    resources: [PDFName: PDFObject],
    limits: PDFGraphicsLimits
  ) {
    self.document = document
    self.revision = revision
    self.limits = limits
    scopes = [resources]
  }

  func push(resources: [PDFName: PDFObject]?) throws {
    guard scopes.count < limits.maximumResourceDepth else {
      throw PDFGraphicsError.limitExceeded("PDF resource nesting limit exceeded.", location: nil)
    }
    scopes.append(resources ?? scopes.last ?? [:])
  }

  func pop() { if scopes.count > 1 { scopes.removeLast() } }

  func enter(_ reference: PDFObjectReference) throws {
    guard !activeReusableResources.contains(reference) else {
      throw PDFGraphicsError.limitExceeded("Cyclic PDF reusable resource.", location: nil)
    }
    guard activeReusableResources.count < limits.maximumResourceDepth else {
      throw PDFGraphicsError.limitExceeded("PDF reusable-resource nesting limit exceeded.", location: nil)
    }
    activeReusableResources.insert(reference)
  }

  func leave(_ reference: PDFObjectReference) { activeReusableResources.remove(reference) }

  func resource(category: PDFName, name: PDFName) async throws -> PDFIndirectObject? {
    for scope in scopes.reversed() {
      guard let categoryObject = scope[category] else { continue }
      let categoryValue = try await resolvedValue(categoryObject)
      guard case .dictionary(let dictionary) = categoryValue else { throw PDFObjectAccess.TypeMismatch.dictionary }
      guard let entry = dictionary[name] else { return nil }
      guard case .reference(let reference) = entry else {
        return PDFIndirectObject(
          reference: try PDFObjectReference(objectNumber: 1, generationNumber: 0),
          value: .value(entry),
          sourceRange: nil,
          provenance: .file,
          definitionRevision: revision
        )
      }
      return try await document.resolve(reference, in: revision)
    }
    return nil
  }

  func colorSpace(named name: PDFName) async throws -> ResolvedColorSpace {
    if let cached = colorSpaceCache[name] { return cached }
    if let defaultName = Self.defaultColorSpaceName(for: name),
      let defaultObject = try await resourceObject(category: "ColorSpace", name: defaultName)
    {
      let resolved: ResolvedColorSpace
      if case .name(let identity) = defaultObject, identity == name {
        resolved = try standardColorSpace(name)!
      } else {
        resolved = try await colorSpace(defaultObject, depth: 0)
      }
      colorSpaceCache[name] = resolved
      return resolved
    }
    if let standard = try standardColorSpace(name) { return standard }
    guard let resourceObject = try await resourceObject(category: "ColorSpace", name: name) else {
      throw PDFObjectAccess.TypeMismatch.name
    }
    let resolved = try await colorSpace(resourceObject, depth: 0)
    colorSpaceCache[name] = resolved
    return resolved
  }

  func colorSpace(_ object: PDFObject, depth: Int = 0) async throws -> ResolvedColorSpace {
    guard depth < limits.maximumResourceDepth else {
      throw PDFGraphicsError.limitExceeded("PDF color-space nesting limit exceeded.", location: nil)
    }
    let value = try await resolvedValue(object)
    if case .name(let name) = value { return try await colorSpace(named: name) }
    let values = try PDFObjectAccess.array(value)
    guard let familyObject = values.first else { throw PDFObjectAccess.TypeMismatch.array }
    let family = try PDFObjectAccess.name(familyObject).pdfGraphicsString
    switch family {
    case "DeviceGray", "G": return try standardColorSpace("DeviceGray")!
    case "DeviceRGB", "RGB": return try standardColorSpace("DeviceRGB")!
    case "DeviceCMYK", "CMYK": return try standardColorSpace("DeviceCMYK")!
    case "CalGray":
      let dictionary = try PDFObjectAccess.dictionary(values[1])
      let white = try xyz(dictionary["WhitePoint"])
      return cieSpace(
        description: .cieBasedA(whitePoint: white),
        componentCount: 1,
        converter: { components in .deviceGray(components[0]) }
      )
    case "CalRGB", "Lab":
      let dictionary = try PDFObjectAccess.dictionary(values[1])
      let white = try xyz(dictionary["WhitePoint"])
      return cieSpace(
        description: .cieBasedABC(whitePoint: white),
        componentCount: 3,
        converter: { components in
          let value = ColorRGB(red: components[0], green: components[1], blue: components[2]).clamped
          return .deviceRGB(red: value.red, green: value.green, blue: value.blue)
        }
      )
    case "ICCBased":
      guard values.count == 2, case .reference(let reference) = values[1] else {
        throw PDFObjectAccess.TypeMismatch.array
      }
      let object = try await document.resolve(reference, in: revision)
      guard case .stream(let stream) = object.value else { throw PDFObjectAccess.TypeMismatch.array }
      let count = try PDFObjectAccess.integer(stream.dictionary["N"] ?? .null)
      guard [1, 3, 4].contains(count) else { throw PDFObjectAccess.TypeMismatch.integer }
      try validateICCProfile(try await document.decodedBytes(of: stream), componentCount: count)
      if diagnosedICCProfiles.insert(reference).inserted {
        diagnostics.append(PDFGraphicsDiagnostic(
          identifier: "pdf.graphics.icc-alternate",
          message: "ICCBased color uses its validated Alternate because portable ICC realization is unavailable.",
          severity: .warning
        ))
      }
      if let alternate = stream.dictionary["Alternate"] {
        let resolved = try await colorSpace(alternate, depth: depth + 1)
        guard resolved.description.componentCount == count else { throw PDFObjectAccess.TypeMismatch.array }
        return resolved
      }
      return try standardColorSpace(PDFName(count == 1 ? "DeviceGray" : count == 3 ? "DeviceRGB" : "DeviceCMYK"))!
    case "Indexed", "I":
      guard values.count == 4 else { throw PDFObjectAccess.TypeMismatch.array }
      let base = try await colorSpace(values[1], depth: depth + 1)
      let maximum = try PDFObjectAccess.integer(values[2])
      guard maximum >= 0, maximum <= 255 else { throw PDFObjectAccess.TypeMismatch.integer }
      let lookup: Data
      switch try await resolvedValue(values[3]) {
      case .string(let string): lookup = string.bytes
      default: throw PDFObjectAccess.TypeMismatch.array
      }
      let expected = (maximum + 1) * base.description.componentCount
      guard lookup.count >= expected else { throw PDFObjectAccess.TypeMismatch.array }
      return ResolvedColorSpace(
        description: .indexed(base: base.description, maximumIndex: maximum),
        realization: GraphicsColorSpaceRealization(
          componentRanges: [0...Double(maximum)],
          indexedLookup: Data(lookup.prefix(expected)),
          alternativeSpace: base.description
        ),
        initialComponents: [0],
        makePaint: { components in
          guard components.count == 1 else { throw PDFObjectAccess.TypeMismatch.number }
          let index = min(maximum, max(0, Int(components[0].rounded())))
          let start = index * base.description.componentCount
          let baseComponents = lookup[start..<(start + base.description.componentCount)].map { Double($0) / 255 }
          return try base.makePaint(baseComponents)
        }
      )
    case "Separation":
      guard values.count == 4 else { throw PDFObjectAccess.TypeMismatch.array }
      let colorant = try PDFObjectAccess.name(values[1]).pdfGraphicsString
      let alternative = try await colorSpace(values[2], depth: depth + 1)
      let function = try await colorFunction(values[3], depth: depth + 1)
      let transform = try sampledTransform(function, inputCount: 1, outputCount: alternative.description.componentCount)
      return ResolvedColorSpace(
        description: .separation(name: colorant, alternative: alternative.description),
        realization: GraphicsColorSpaceRealization(
          componentRanges: [0...1],
          alternativeSpace: alternative.description,
          sampledTransform: transform
        ),
        initialComponents: [1],
        makePaint: { components in
          guard components.count == 1 else { throw PDFObjectAccess.TypeMismatch.number }
          let alternate = try alternative.makePaint(function.evaluate(components))
          return .color(.named(
            space: .separation(name: colorant, alternative: alternative.description),
            colorants: [colorant],
            tints: components,
            alternative: Self.colorValueValue(from: alternate)
          ))
        }
      )
    case "DeviceN":
      guard values.count >= 4 else { throw PDFObjectAccess.TypeMismatch.array }
      let names = try PDFObjectAccess.array(values[1]).map { try PDFObjectAccess.name($0).pdfGraphicsString }
      let alternative = try await colorSpace(values[2], depth: depth + 1)
      let function = try await colorFunction(values[3], depth: depth + 1)
      let transform = try sampledTransform(
        function,
        inputCount: names.count,
        outputCount: alternative.description.componentCount
      )
      return ResolvedColorSpace(
        description: .deviceN(names: names, alternative: alternative.description),
        realization: GraphicsColorSpaceRealization(
          componentRanges: Array(repeating: 0...1, count: names.count),
          alternativeSpace: alternative.description,
          sampledTransform: transform
        ),
        initialComponents: Array(repeating: 1, count: names.count),
        makePaint: { components in
          guard components.count == names.count else { throw PDFObjectAccess.TypeMismatch.number }
          return .color(.named(
            space: .deviceN(names: names, alternative: alternative.description),
            colorants: names,
            tints: components,
            alternative: Self.colorValueValue(from: try alternative.makePaint(function.evaluate(components)))
          ))
        }
      )
    case "Pattern":
      let underlying = values.count > 1 ? try await colorSpace(values[1], depth: depth + 1) : nil
      var result = ResolvedColorSpace(
        description: .pattern(underlying: underlying?.description),
        realization: underlying?.realization,
        initialComponents: underlying?.initialComponents ?? [],
        makePaint: { _ in .pattern(.empty) }
      )
      result.underlyingMakePaint = underlying?.makePaint
      return result
    default:
      throw PDFObjectAccess.TypeMismatch.name
    }
  }

  func colorFunction(_ object: PDFObject, depth: Int = 0) async throws -> ColorFunction {
    guard depth < limits.maximumResourceDepth else {
      throw PDFGraphicsError.limitExceeded("PDF function nesting limit exceeded.", location: nil)
    }
    let resolved: PDFResolvedObject
    if case .reference(let reference) = object {
      resolved = try await document.resolve(reference, in: revision).value
    } else {
      resolved = .value(object)
    }
    let dictionary: [PDFName: PDFObject]
    let streamData: Data?
    switch resolved {
    case .value(.dictionary(let value)):
      dictionary = value
      streamData = nil
    case .stream(let stream):
      dictionary = stream.dictionary
      streamData = try await document.decodedBytes(of: stream)
    default: throw PDFObjectAccess.TypeMismatch.dictionary
    }
    let type = try PDFObjectAccess.integer(dictionary["FunctionType"] ?? .null)
    let domain = try ranges(dictionary["Domain"])
    let range = try dictionary["Range"].map(ranges)
    switch type {
    case 0:
      guard let streamData, let range else { throw PDFObjectAccess.TypeMismatch.dictionary }
      return .sampled(try ColorSampledFunction(
        domain: domain,
        range: range,
        size: try PDFObjectAccess.array(dictionary["Size"] ?? .null).map(PDFObjectAccess.integer),
        bitsPerSample: try PDFObjectAccess.integer(dictionary["BitsPerSample"] ?? .null),
        order: try dictionary["Order"].map(PDFObjectAccess.integer) ?? 1,
        encode: try dictionary["Encode"].map(PDFObjectAccess.numbers),
        decode: try dictionary["Decode"].map(PDFObjectAccess.numbers),
        sampleData: streamData
      ))
    case 2:
      guard domain.count == 1 else { throw PDFObjectAccess.TypeMismatch.array }
      return .exponential(try ColorExponentialFunction(
        domain: domain[0],
        range: range,
        c0: try dictionary["C0"].map(PDFObjectAccess.numbers) ?? [0],
        c1: try dictionary["C1"].map(PDFObjectAccess.numbers) ?? [1],
        exponent: try PDFObjectAccess.number(dictionary["N"] ?? .null)
      ))
    case 3:
      guard domain.count == 1 else { throw PDFObjectAccess.TypeMismatch.array }
      var functions: [ColorFunction] = []
      for function in try PDFObjectAccess.array(dictionary["Functions"] ?? .null) {
        functions.append(try await colorFunction(function, depth: depth + 1))
      }
      return .stitching(try ColorStitchingFunction(
        domain: domain[0],
        range: range,
        functions: functions,
        bounds: try PDFObjectAccess.numbers(dictionary["Bounds"] ?? .null),
        encode: try PDFObjectAccess.numbers(dictionary["Encode"] ?? .null)
      ))
    case 4:
      guard let streamData, let range else { throw PDFObjectAccess.TypeMismatch.dictionary }
      return .calculator(try ColorCalculatorFunction(
        domain: domain,
        range: range,
        program: streamData
      ))
    default: throw PDFObjectAccess.TypeMismatch.integer
    }
  }

  func componentFunction(_ object: PDFObject) async throws -> GraphicsComponentFunction {
    if case .name(let name) = object {
      guard name.pdfGraphicsString == "Identity" || name.pdfGraphicsString == "Default" else {
        throw PDFObjectAccess.TypeMismatch.name
      }
      return .identity
    }
    let function = try await colorFunction(object)
    guard function.inputCount == 1, function.outputCount == 1 else {
      throw PDFObjectAccess.TypeMismatch.array
    }
    var samples: [Double] = []
    samples.reserveCapacity(257)
    for index in 0...256 { samples.append(try function.evaluate([Double(index) / 256])[0]) }
    return try GraphicsComponentFunction(samples: samples)
  }

  func resourceObject(category: PDFName, name: PDFName) async throws -> PDFObject? {
    for scope in scopes.reversed() {
      guard let categoryObject = scope[category] else { continue }
      let categoryValue = try await resolvedValue(categoryObject)
      guard case .dictionary(let dictionary) = categoryValue else { throw PDFObjectAccess.TypeMismatch.dictionary }
      return dictionary[name]
    }
    return nil
  }

  func resolvedResource(category: PDFName, name: PDFName) async throws -> PDFIndirectObject? {
    guard let object = try await resourceObject(category: category, name: name) else { return nil }
    guard case .reference(let reference) = object else { return nil }
    return try await document.resolve(reference, in: revision)
  }

  func resolvedObject(_ object: PDFObject) async throws -> PDFObject {
    try await resolvedValue(object)
  }

  private func resolvedValue(_ object: PDFObject) async throws -> PDFObject {
    guard case .reference(let reference) = object else { return object }
    switch try await document.resolve(reference, in: revision).value {
    case .value(let value): return value
    case .stream: throw PDFObjectAccess.TypeMismatch.dictionary
    }
  }

  private func standardColorSpace(_ name: PDFName) throws -> ResolvedColorSpace? {
    switch name.pdfGraphicsString {
    case "DeviceGray", "G":
      return ResolvedColorSpace(
        description: .deviceGray,
        realization: nil,
        initialComponents: [0],
        makePaint: { values in
          guard values.count == 1 else { throw PDFObjectAccess.TypeMismatch.number }
          return .deviceGray(values[0])
        }
      )
    case "DeviceRGB", "RGB":
      return ResolvedColorSpace(
        description: .deviceRGB,
        realization: nil,
        initialComponents: [0, 0, 0],
        makePaint: { values in
          guard values.count == 3 else { throw PDFObjectAccess.TypeMismatch.number }
          return .deviceRGB(red: values[0], green: values[1], blue: values[2])
        }
      )
    case "DeviceCMYK", "CMYK":
      return ResolvedColorSpace(
        description: .deviceCMYK,
        realization: nil,
        initialComponents: [0, 0, 0, 1],
        makePaint: { values in
          guard values.count == 4 else { throw PDFObjectAccess.TypeMismatch.number }
          return .deviceCMYK(cyan: values[0], magenta: values[1], yellow: values[2], black: values[3])
        }
      )
    default: return nil
    }
  }

  private func validateICCProfile(_ data: Data, componentCount: Int) throws {
    guard data.count >= 128 else { throw PDFObjectAccess.TypeMismatch.array }
    let declaredLength = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    let expectedSignature = switch componentCount {
    case 1: Data("GRAY".utf8)
    case 3: Data("RGB ".utf8)
    case 4: Data("CMYK".utf8)
    default: Data()
    }
    guard declaredLength >= 128, declaredLength <= data.count,
      data[36..<40] == Data("acsp".utf8),
      data[16..<20] == expectedSignature
    else { throw PDFObjectAccess.TypeMismatch.array }
  }

  private func cieSpace(
    description: GraphicsColorSpaceDescription,
    componentCount: Int,
    converter: @escaping @Sendable ([Double]) throws -> GraphicsPaint
  ) -> ResolvedColorSpace {
    ResolvedColorSpace(
      description: description,
      realization: GraphicsColorSpaceRealization(
        componentRanges: Array(repeating: 0...1, count: componentCount)
      ),
      initialComponents: Array(repeating: 0, count: componentCount),
      makePaint: converter
    )
  }

  private func xyz(_ object: PDFObject?) throws -> ColorXYZ {
    let values = try PDFObjectAccess.numbers(object ?? .null)
    guard values.count == 3, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
      throw PDFObjectAccess.TypeMismatch.array
    }
    return ColorXYZ(x: values[0], y: values[1], z: values[2])
  }

  private func ranges(_ object: PDFObject?) throws -> [ColorComponentRange] {
    let values = try PDFObjectAccess.numbers(object ?? .null)
    guard values.count.isMultiple(of: 2), !values.isEmpty else { throw PDFObjectAccess.TypeMismatch.array }
    return try stride(from: 0, to: values.count, by: 2).map {
      try ColorComponentRange(values[$0], values[$0 + 1])
    }
  }

  private func sampledTransform(
    _ function: ColorFunction,
    inputCount: Int,
    outputCount: Int
  ) throws -> GraphicsSampledColorTransform {
    guard function.inputCount == inputCount, function.outputCount == outputCount else {
      throw PDFObjectAccess.TypeMismatch.array
    }
    let size = Array(repeating: 9, count: inputCount)
    var sampleCount = 1
    for dimension in size {
      let product = sampleCount.multipliedReportingOverflow(by: dimension)
      guard !product.overflow, product.partialValue * outputCount <= 1_000_000 else {
        throw PDFGraphicsError.limitExceeded("PDF color transform sample limit exceeded.", location: nil)
      }
      sampleCount = product.partialValue
    }
    var data = Data(capacity: sampleCount * outputCount * 2)
    for linearIndex in 0..<sampleCount {
      var remainder = linearIndex
      var input = Array(repeating: 0.0, count: inputCount)
      for dimension in 0..<inputCount {
        input[dimension] = Double(remainder % 9) / 8
        remainder /= 9
      }
      for value in try function.evaluate(input) {
        var encoded = UInt16((min(1, max(0, value)) * 65_535).rounded()).bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
      }
    }
    return GraphicsSampledColorTransform(size: size, outputComponentCount: outputCount, samples: data)
  }

  private static func colorValueValue(from paint: GraphicsPaint) -> GraphicsColorValue {
    switch paint {
    case .deviceGray(let value): .deviceGray(value)
    case .deviceRGB(let red, let green, let blue): .deviceRGB(ColorRGB(red: red, green: green, blue: blue))
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      .deviceCMYK(ColorCMYK(cyan: cyan, magenta: magenta, yellow: yellow, black: black))
    case .color(let value): value
    case .pattern: .deviceGray(0)
    }
  }

  private static func defaultColorSpaceName(for name: PDFName) -> PDFName? {
    switch name.pdfGraphicsString {
    case "DeviceGray", "G": "DefaultGray"
    case "DeviceRGB", "RGB": "DefaultRGB"
    case "DeviceCMYK", "CMYK": "DefaultCMYK"
    default: nil
    }
  }
}
