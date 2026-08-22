import Foundation
import SolidPDF
import SolidPostScript

extension PDFGraphicsInstructionHandler {
  func executeInlineImage(_ image: PDFInlineImage) async throws {
    let dictionary = canonicalInlineDictionary(image.dictionary)
    let instruction = PDFContentInstruction(operands: [], name: "BI", location: image.location)
    let width = try PDFObjectAccess.integer(dictionary["Width"] ?? .null)
    let height = try PDFObjectAccess.integer(dictionary["Height"] ?? .null)
    let imageMask = try boolean(dictionary["ImageMask"], default: false)
    let bits = imageMask ? 1 : try PDFObjectAccess.integer(dictionary["BitsPerComponent"] ?? .null)
    let colorSpace: PDFGraphicsResourceResolver<Source>.ResolvedColorSpace?
    if imageMask {
      colorSpace = nil
    } else {
      guard let color = dictionary["ColorSpace"] else { throw malformed("Inline image lacks ColorSpace.", instruction) }
      colorSpace = try await resources.colorSpace(color)
    }
    let sourceCount = imageMask ? 1 : colorSpace!.description.componentCount
    let decode = try dictionary["Decode"].map(PDFObjectAccess.numbers)
      ?? Array(repeating: [0.0, 1.0], count: sourceCount).flatMap { $0 }
    guard decode.count == sourceCount * 2 else { throw malformed("Inline-image Decode has the wrong length.", instruction) }
    let transform = imageTransform(width: width, height: height)
    let identifier = GraphicsResourceIdentifier(
      rawValue: "pdf:inline:r\(image.location.revision.ordinal):p\(image.location.pageIndex):\(image.location.decodedOffset)"
    )
    let descriptor = GraphicsImageDescriptor(
      width: width,
      height: height,
      kind: imageMask ? .mask(state.nonstroking.paint) : .color(deviceImageSpace(for: colorSpace!.description)),
      sourceColorSpace: colorSpace?.description,
      sourceBitsPerComponent: bits,
      sourceComponentCount: sourceCount,
      decode: decode,
      colorRealization: colorSpace?.realization,
      imageToDevice: transform,
      interpolate: try boolean(dictionary["Interpolate"], default: false),
      resourceIdentifier: identifier
    )
    let event = GraphicsEvent(
      operation: .paint(.image(descriptor)),
      before: state.snapshot(stroking: false),
      after: state.snapshot(stroking: false),
      origin: origin(image.location, resource: identifier)
    )
    try output.beginImage(event)
    do {
      let rowBytes = (try checkedProduct(width, sourceCount, bits) + 7) / 8
      guard image.data.count == rowBytes * height else { throw malformed("Inline-image byte count is invalid.", instruction) }
      for row in 0..<height {
        let source = image.data[(row * rowBytes)..<((row + 1) * rowBytes)]
        let samples = unpack(Data(source), count: width * sourceCount, bits: bits)
        let maximum = Double((1 << bits) - 1)
        let sourceComponents = samples.enumerated().map { index, sample -> Float in
          let component = index % sourceCount
          let value = Double(sample) / maximum
          return Float(decode[component * 2] + value * (decode[component * 2 + 1] - decode[component * 2]))
        }
        let components = imageMask ? sourceComponents : try deviceComponents(sourceComponents, colorSpace: colorSpace!)
        try output.writeImageRows(.init(
          startRow: row,
          rowCount: 1,
          components: components,
          sourceComponents: components == sourceComponents ? nil : sourceComponents
        ))
      }
      try output.endImage()
    } catch {
      output.abortImage()
      throw error
    }
  }

  func paintXObject(_ instruction: PDFContentInstruction) async throws {
    try operands(instruction, count: 1)
    let name = try PDFObjectAccess.name(instruction.operands[0])
    guard let object = try await resources.resolvedResource(category: "XObject", name: name) else {
      throw malformed("Missing or direct XObject resource.", instruction)
    }
    guard case .stream(let stream) = object.value else { throw malformed("XObject is not a stream.", instruction) }
    let subtype = try PDFObjectAccess.name(stream.dictionary["Subtype"] ?? .null).pdfGraphicsString
    switch subtype {
    case "Image": try await paintImage(stream, reference: object.reference, instruction: instruction)
    case "Form": try await paintForm(stream, reference: object.reference, instruction: instruction)
    case "PS": return
    case "Ref": throw PDFGraphicsError.unsupported(.referenceXObject, location: instruction.location)
    default: throw malformed("Unknown XObject subtype.", instruction)
    }
  }

  func paintImage(
    _ stream: PDFStreamObject,
    reference: PDFObjectReference,
    instruction: PDFContentInstruction
  ) async throws {
    let dictionary = stream.dictionary
    let width = try PDFObjectAccess.integer(dictionary["Width"] ?? .null)
    let height = try PDFObjectAccess.integer(dictionary["Height"] ?? .null)
    guard width > 0, height > 0,
      width <= limits.maximumImagePixels / height,
      width * height <= limits.maximumImagePixels
    else { throw PDFGraphicsError.limitExceeded("PDF image pixel limit exceeded.", location: instruction.location) }
    let imageMask = try boolean(dictionary["ImageMask"], default: false)
    let bits = imageMask ? 1 : try PDFObjectAccess.integer(dictionary["BitsPerComponent"] ?? .null)
    guard [1, 2, 4, 8, 16].contains(bits) else { throw malformed("Unsupported image sample precision.", instruction) }
    let colorSpace: PDFGraphicsResourceResolver<Source>.ResolvedColorSpace?
    if imageMask {
      colorSpace = nil
    } else {
      guard let colorObject = dictionary["ColorSpace"] else { throw malformed("Image ColorSpace is missing.", instruction) }
      colorSpace = try await resources.colorSpace(colorObject)
    }
    let sourceCount = imageMask ? 1 : colorSpace!.description.componentCount
    let decode = try dictionary["Decode"].map(PDFObjectAccess.numbers)
      ?? Array(repeating: [0.0, 1.0], count: sourceCount).flatMap { $0 }
    guard decode.count == sourceCount * 2 else { throw malformed("Image Decode has the wrong length.", instruction) }
    let interpolate = try boolean(dictionary["Interpolate"], default: false)
    let mask = try await imageMaskDescriptor(
      dictionary,
      transform: imageTransform(width: width, height: height),
      location: instruction.location
    )
    if dictionary["SMask"] != nil { throw PDFGraphicsError.unsupported(.transparency("SMask"), location: instruction.location) }

    let kind: GraphicsImageKind
    if imageMask {
      kind = .mask(state.nonstroking.paint)
    } else {
      kind = .color(deviceImageSpace(for: colorSpace!.description))
    }
    let descriptor = GraphicsImageDescriptor(
      width: width,
      height: height,
      kind: kind,
      sourceType: mask == nil ? .sampled : (isColorKey(mask!) ? .colorKeyMask : .explicitMask),
      sourceColorSpace: colorSpace?.description,
      sourceBitsPerComponent: bits,
      sourceComponentCount: sourceCount,
      decode: decode,
      colorRealization: colorSpace?.realization,
      imageToDevice: imageTransform(width: width, height: height),
      interpolate: interpolate,
      mask: mask,
      resourceIdentifier: resourceIdentifier(reference)
    )
    let event = GraphicsEvent(
      operation: .paint(.image(descriptor)),
      before: state.snapshot(stroking: false),
      after: state.snapshot(stroking: false),
      origin: origin(instruction.location, resource: descriptor.resourceIdentifier)
    )
    try output.beginImage(event)
    do {
      try await streamImageRows(
        stream,
        width: width,
        height: height,
        bits: bits,
        sourceCount: sourceCount,
        decode: decode,
        colorSpace: colorSpace,
        imageMask: imageMask
      )
      try output.endImage()
    } catch {
      output.abortImage()
      throw error
    }
  }

  private func streamImageRows(
    _ stream: PDFStreamObject,
    width: Int,
    height: Int,
    bits: Int,
    sourceCount: Int,
    decode: [Double],
    colorSpace: PDFGraphicsResourceResolver<Source>.ResolvedColorSpace?,
    imageMask: Bool
  ) async throws {
    let rowBits = try checkedProduct(width, sourceCount, bits)
    let rowBytes = (rowBits + 7) / 8
    let decoded = try await resources.document.decodedStream(of: stream)
    defer { Task { await decoded.close() } }
    var pending = Data()
    var row = 0
    for try await chunk in decoded {
      pending.append(chunk)
      while pending.count >= rowBytes, row < height {
        let source = Data(pending.prefix(rowBytes))
        pending.removeFirst(rowBytes)
        let samples = unpack(source, count: width * sourceCount, bits: bits)
        var sourceComponents: [Float] = []
        sourceComponents.reserveCapacity(samples.count)
        let maximum = Double((1 << bits) - 1)
        for (index, sample) in samples.enumerated() {
          let component = index % sourceCount
          let normalized = Double(sample) / maximum
          sourceComponents.append(Float(decode[component * 2] + normalized * (decode[component * 2 + 1] - decode[component * 2])))
        }
        let components: [Float]
        if imageMask {
          components = sourceComponents
        } else {
          components = try deviceComponents(sourceComponents, colorSpace: colorSpace!)
        }
        var raw = Data(capacity: samples.count * 2)
        for sample in samples {
          var value = sample.bigEndian
          withUnsafeBytes(of: &value) { raw.append(contentsOf: $0) }
        }
        try output.writeImageRows(GraphicsImageRows(
          startRow: row,
          rowCount: 1,
          components: components,
          sourceComponents: components == sourceComponents ? nil : sourceComponents,
          rawSamples: raw
        ))
        row += 1
      }
      if row == height, !pending.isEmpty { throw PDFObjectAccess.TypeMismatch.array }
    }
    guard row == height, pending.isEmpty else { throw PDFObjectAccess.TypeMismatch.array }
  }

  private func deviceComponents(
    _ source: [Float],
    colorSpace: PDFGraphicsResourceResolver<Source>.ResolvedColorSpace
  ) throws -> [Float] {
    let count = colorSpace.description.componentCount
    var result: [Float] = []
    for offset in stride(from: 0, to: source.count, by: count) {
      let paint = try colorSpace.makePaint(source[offset..<(offset + count)].map(Double.init))
      switch paint {
      case .deviceGray(let gray): result.append(Float(gray))
      case .deviceRGB(let red, let green, let blue): result.append(contentsOf: [Float(red), Float(green), Float(blue)])
      case .deviceCMYK(let cyan, let magenta, let yellow, let black):
        result.append(contentsOf: [Float(cyan), Float(magenta), Float(yellow), Float(black)])
      case .color(let color):
        let rgb = GraphicsPaint.color(color).rgbComponents
        result.append(contentsOf: [Float(rgb.red), Float(rgb.green), Float(rgb.blue)])
      case .pattern: throw PDFObjectAccess.TypeMismatch.array
      }
    }
    return result
  }

  private func imageMaskDescriptor(
    _ dictionary: [PDFName: PDFObject],
    transform: GraphicsMatrix,
    location: PDFContentLocation
  ) async throws -> GraphicsImageMaskDescriptor? {
    guard let object = dictionary["Mask"] else { return nil }
    let value = try await resources.resolvedObject(object)
    switch value {
    case .array(let values):
      let numbers = try values.map(PDFObjectAccess.integer)
      guard numbers.count.isMultiple(of: 2) else { throw PDFObjectAccess.TypeMismatch.array }
      return .colorKey(ranges: try stride(from: 0, to: numbers.count, by: 2).map {
        guard let lower = UInt16(exactly: numbers[$0]), let upper = UInt16(exactly: numbers[$0 + 1]), lower <= upper else {
          throw PDFObjectAccess.TypeMismatch.integer
        }
        return GraphicsImageSampleRange(lowerBound: lower, upperBound: upper)
      })
    default:
      // Explicit mask streams are resolved and transferred in a second bounded transaction later in this tranche.
      throw PDFGraphicsError.unsupported(.transparency("Mask"), location: location)
    }
  }

  private func imageTransform(width: Int, height: Int) -> GraphicsMatrix {
    GraphicsMatrix(a: 1 / Double(width), b: 0, c: 0, d: -1 / Double(height), tx: 0, ty: 1)
      .concatenated(with: state.matrix)
  }

  private func deviceImageSpace(for description: GraphicsColorSpaceDescription) -> GraphicsImageColorSpace {
    switch description {
    case .deviceGray, .cieBasedA: .deviceGray
    case .deviceCMYK, .cieBasedDEFG: .deviceCMYK
    default: .deviceRGB
    }
  }

  private func unpack(_ data: Data, count: Int, bits: Int) -> [UInt16] {
    if bits == 16 {
      return stride(from: 0, to: min(data.count, count * 2), by: 2).map {
        UInt16(data[$0]) << 8 | UInt16(data[$0 + 1])
      }
    }
    var result: [UInt16] = []
    result.reserveCapacity(count)
    let mask = (1 << bits) - 1
    for index in 0..<count {
      let bit = index * bits
      let shift = 8 - bits - bit % 8
      result.append(UInt16((Int(data[bit / 8]) >> shift) & mask))
    }
    return result
  }

  private func checkedProduct(_ values: Int...) throws -> Int {
    var result = 1
    for value in values {
      let next = result.multipliedReportingOverflow(by: value)
      guard !next.overflow else { throw PDFObjectAccess.TypeMismatch.integer }
      result = next.partialValue
    }
    return result
  }

  private func boolean(_ object: PDFObject?, default value: Bool) throws -> Bool {
    guard let object else { return value }
    guard case .boolean(let result) = object else { throw PDFObjectAccess.TypeMismatch.integer }
    return result
  }

  private func isColorKey(_ mask: GraphicsImageMaskDescriptor) -> Bool {
    if case .colorKey = mask { return true }
    return false
  }

  private func canonicalInlineDictionary(_ dictionary: [PDFName: PDFObject]) -> [PDFName: PDFObject] {
    let keys: [(PDFName, PDFName)] = [
      ("BPC", "BitsPerComponent"), ("CS", "ColorSpace"), ("D", "Decode"),
      ("DP", "DecodeParms"), ("F", "Filter"), ("H", "Height"),
      ("IM", "ImageMask"), ("I", "Interpolate"), ("W", "Width"),
    ]
    var result = dictionary
    for (short, canonical) in keys where result[canonical] == nil { result[canonical] = result[short] }
    if case .name(let name)? = result["ColorSpace"] {
      let canonical: PDFName? = switch name.pdfGraphicsString {
      case "G": "DeviceGray"
      case "RGB": "DeviceRGB"
      case "CMYK": "DeviceCMYK"
      case "I": "Indexed"
      default: nil
      }
      if let canonical { result["ColorSpace"] = .name(canonical) }
    }
    return result
  }

  func resourceIdentifier(_ reference: PDFObjectReference) -> GraphicsResourceIdentifier {
    GraphicsResourceIdentifier(
      rawValue: "pdf:r\(resources.revision.ordinal):o\(reference.objectNumber):\(reference.generationNumber)"
    )
  }

}
