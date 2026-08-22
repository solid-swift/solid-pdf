import Foundation
import SolidPDF
import SolidPostScript

extension PDFGraphicsInstructionHandler {
  private struct ResolvedImageMask {
    let descriptor: GraphicsImageMaskDescriptor
    let stream: PDFStreamObject?
    let decode: [Double]
  }

  func inlineImageByteCount(
    dictionary source: [PDFName: PDFObject],
    location: PDFContentLocation
  ) async throws -> Int {
    let dictionary = canonicalInlineDictionary(source)
    let width = try PDFObjectAccess.integer(dictionary["Width"] ?? .null)
    let height = try PDFObjectAccess.integer(dictionary["Height"] ?? .null)
    let imageMask = try boolean(dictionary["ImageMask"], default: false)
    let bits = imageMask ? 1 : try PDFObjectAccess.integer(dictionary["BitsPerComponent"] ?? .null)
    guard width > 0, height > 0, [1, 2, 4, 8, 16].contains(bits),
      width <= limits.maximumImagePixels / height,
      width * height <= limits.maximumImagePixels
    else {
      throw PDFGraphicsError.limitExceeded("PDF inline-image pixel limit exceeded.", location: location)
    }
    let componentCount: Int
    if imageMask {
      componentCount = 1
    } else {
      guard let color = dictionary["ColorSpace"] else {
        throw PDFGraphicsError.malformedContent(
          message: "Inline image lacks ColorSpace.",
          operatorName: "BI",
          location: location
        )
      }
      componentCount = try await resources.colorSpace(color).description.componentCount
    }
    let rowBits = try checkedProduct(width, componentCount, bits)
    return try checkedProduct((rowBits + 7) / 8, height)
  }

  func executeInlineImage(_ image: PDFInlineImage) async throws {
    let dictionary = canonicalInlineDictionary(image.dictionary)
    let instruction = PDFContentInstruction(operands: [], name: "BI", location: image.location)
    do {
      let width = try PDFObjectAccess.integer(dictionary["Width"] ?? .null)
      let height = try PDFObjectAccess.integer(dictionary["Height"] ?? .null)
      let imageMask = try boolean(dictionary["ImageMask"], default: false)
      let bits = imageMask ? 1 : try PDFObjectAccess.integer(dictionary["BitsPerComponent"] ?? .null)
      guard width > 0, height > 0, [1, 2, 4, 8, 16].contains(bits),
        width <= limits.maximumImagePixels / height,
        width * height <= limits.maximumImagePixels
      else {
        throw PDFGraphicsError.limitExceeded("PDF inline-image pixel limit exceeded.", location: image.location)
      }
      let colorSpace: PDFGraphicsResourceResolver<Source>.ResolvedColorSpace?
      if imageMask {
        colorSpace = nil
      } else {
        guard let color = dictionary["ColorSpace"] else {
          throw malformed("Inline image lacks ColorSpace.", instruction)
        }
        colorSpace = try await resources.colorSpace(color)
      }
      let sourceCount = imageMask ? 1 : colorSpace!.description.componentCount
      let decode = try dictionary["Decode"].map(PDFObjectAccess.numbers)
        ?? Array(repeating: [0.0, 1.0], count: sourceCount).flatMap { $0 }
      guard decode.count == sourceCount * 2 else {
        throw malformed("Inline-image Decode has the wrong length.", instruction)
      }
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
        guard image.data.count == (try checkedProduct(rowBytes, height)) else {
          throw malformed("Inline-image byte count is invalid.", instruction)
        }
        for row in 0..<height {
          let source = image.data[(row * rowBytes)..<((row + 1) * rowBytes)]
          let samples = unpack(Data(source), count: width * sourceCount, bits: bits)
          let maximum = Double((1 << bits) - 1)
          let sourceComponents = samples.enumerated().map { index, sample -> Float in
            let component = index % sourceCount
            let value = Double(sample) / maximum
            return Float(decode[component * 2] + value * (decode[component * 2 + 1] - decode[component * 2]))
          }
          let components = imageMask
            ? sourceComponents
            : try deviceComponents(sourceComponents, colorSpace: colorSpace!)
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
    } catch let error as PDFGraphicsError {
      throw error
    } catch let error as PDFParsingError {
      throw error
    } catch {
      throw malformed("Invalid inline-image dictionary or samples.", instruction)
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
    case "PS":
      recordDiagnostic(PDFGraphicsDiagnostic(
        identifier: "pdf.graphics.postscript-xobject-ignored",
        message: "A PostScript XObject produces no marks when rendered as non-PostScript PDF output.",
        severity: .information,
        location: instruction.location
      ))
      return
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
    if imageMask, dictionary["Mask"] != nil {
      throw malformed("An image mask cannot specify another Mask.", instruction)
    }
    let resolvedMask = try await resolveImageMask(
      dictionary,
      sourceComponentCount: sourceCount,
      sourceBitsPerComponent: bits,
      location: instruction.location
    )
    let mask = resolvedMask?.descriptor
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
        imageMask: imageMask,
        location: instruction.location
      )
      if let maskStream = resolvedMask?.stream {
        try await streamMaskRows(
          maskStream,
          descriptor: resolvedMask!.descriptor,
          decode: resolvedMask!.decode,
          instruction: instruction
        )
      }
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
    imageMask: Bool,
    location: PDFContentLocation
  ) async throws {
    let rowBits = try checkedProduct(width, sourceCount, bits)
    let rowBytes = (rowBits + 7) / 8
    guard rowBytes <= limits.maximumScratchBytes else {
      throw PDFGraphicsError.limitExceeded("PDF image row exceeds interpretation scratch.", location: location)
    }
    let decoded = try await resources.document.decodedStream(of: stream)
    defer { Task { await decoded.close() } }
    var pending = Data()
    var row = 0
    for try await chunk in decoded {
      pending.append(chunk)
      guard pending.count <= limits.maximumScratchBytes else {
        throw PDFGraphicsError.limitExceeded("PDF image scratch limit exceeded.", location: location)
      }
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

  private func resolveImageMask(
    _ dictionary: [PDFName: PDFObject],
    sourceComponentCount: Int,
    sourceBitsPerComponent: Int,
    location: PDFContentLocation
  ) async throws -> ResolvedImageMask? {
    guard let object = dictionary["Mask"] else { return nil }
    switch object {
    case .array(let values):
      return try colorKeyMask(
        values,
        sourceComponentCount: sourceComponentCount,
        sourceBitsPerComponent: sourceBitsPerComponent
      )
    case .reference(let reference):
      let resolved = try await resources.document.resolve(reference, in: resources.revision)
      if case .value(.array(let values)) = resolved.value {
        return try colorKeyMask(
          values,
          sourceComponentCount: sourceComponentCount,
          sourceBitsPerComponent: sourceBitsPerComponent
        )
      }
      guard case .stream(let stream) = resolved.value else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let maskDictionary = stream.dictionary
      guard try PDFObjectAccess.name(maskDictionary["Subtype"] ?? .null).pdfGraphicsString == "Image",
        try boolean(maskDictionary["ImageMask"], default: false),
        maskDictionary["ColorSpace"] == nil,
        maskDictionary["Mask"] == nil,
        maskDictionary["SMask"] == nil
      else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let width = try PDFObjectAccess.integer(maskDictionary["Width"] ?? .null)
      let height = try PDFObjectAccess.integer(maskDictionary["Height"] ?? .null)
      let bits = try maskDictionary["BitsPerComponent"].map(PDFObjectAccess.integer) ?? 1
      guard width > 0, height > 0, bits == 1,
        width <= limits.maximumImagePixels / height,
        width * height <= limits.maximumImagePixels
      else { throw PDFGraphicsError.limitExceeded("PDF explicit-mask pixel limit exceeded.", location: location) }
      let decode = try maskDictionary["Decode"].map(PDFObjectAccess.numbers) ?? [0, 1]
      guard decode == [0, 1] || decode == [1, 0] else { throw PDFObjectAccess.TypeMismatch.array }
      return ResolvedImageMask(
        descriptor: .explicit(
          width: width,
          height: height,
          maskToDevice: imageTransform(width: width, height: height),
          interpolate: try boolean(maskDictionary["Interpolate"], default: false)
        ),
        stream: stream,
        decode: decode
      )
    default:
      throw PDFObjectAccess.TypeMismatch.array
    }
  }

  private func colorKeyMask(
    _ values: [PDFObject],
    sourceComponentCount: Int,
    sourceBitsPerComponent: Int
  ) throws -> ResolvedImageMask {
    let numbers = try values.map(PDFObjectAccess.integer)
    guard numbers.count == sourceComponentCount * 2 else { throw PDFObjectAccess.TypeMismatch.array }
    let maximum = sourceBitsPerComponent == 16 ? Int(UInt16.max) : (1 << sourceBitsPerComponent) - 1
    return ResolvedImageMask(descriptor: .colorKey(ranges: try stride(from: 0, to: numbers.count, by: 2).map {
      guard let lower = UInt16(exactly: numbers[$0]), let upper = UInt16(exactly: numbers[$0 + 1]),
        lower <= upper, upper <= maximum
      else { throw PDFObjectAccess.TypeMismatch.integer }
      return GraphicsImageSampleRange(lowerBound: lower, upperBound: upper)
    }), stream: nil, decode: [])
  }

  private func streamMaskRows(
    _ stream: PDFStreamObject,
    descriptor: GraphicsImageMaskDescriptor,
    decode: [Double],
    instruction: PDFContentInstruction
  ) async throws {
    guard case .explicit(let width, let height, _, _) = descriptor else { return }
    let rowBytes = (width + 7) / 8
    let decoded = try await resources.document.decodedStream(of: stream)
    defer { Task { await decoded.close() } }
    var pending = Data()
    var row = 0
    for try await chunk in decoded {
      pending.append(chunk)
      guard pending.count <= limits.maximumScratchBytes else {
        throw PDFGraphicsError.limitExceeded("PDF explicit-mask scratch limit exceeded.", location: instruction.location)
      }
      while pending.count >= rowBytes, row < height {
        let source = Data(pending.prefix(rowBytes))
        pending.removeFirst(rowBytes)
        let opacities = unpack(source, count: width, bits: 1).map { sample -> Float in
          let decoded = decode[0] + Double(sample) * (decode[1] - decode[0])
          return Float(1 - min(1, max(0, decoded)))
        }
        try output.writeImageMaskRows(.init(startRow: row, rowCount: 1, opacities: opacities))
        row += 1
      }
      if row == height, !pending.isEmpty { throw malformed("Explicit image mask has excess data.", instruction) }
    }
    guard row == height, pending.isEmpty else { throw malformed("Explicit image mask is truncated.", instruction) }
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
