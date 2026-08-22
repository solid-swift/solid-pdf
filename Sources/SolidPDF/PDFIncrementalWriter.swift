import Foundation

enum PDFIncrementalObjectBody: Sendable {
  case value(PDFObject)
  case stream(dictionary: [PDFName: PDFObject], bytes: Data)
}

struct PDFIncrementalWriter {
  struct EncodedRevision: Sendable {
    let data: Data
    let appendedByteCount: Int
    let startCrossReferenceOffset: Int64
    let representation: PDFCrossReferenceRepresentation
  }

  let original: Data
  let revision: PDFDocumentRevision
  let objects: [PDFObjectReference: PDFIncrementalObjectBody]
  let limits: PDFIncrementalWritingLimits

  func encode() throws -> EncodedRevision {
    try validateLimits()
    var output = original
    if output.last.map({ $0 != 0x0A && $0 != 0x0D }) ?? false {
      output.append(0x0A)
    }
    let appendedStart = output.count
    let serializer = PDFObjectSerializer(limits: writerLimits)
    var offsets = [PDFObjectReference: Int64]()
    for reference in objects.keys.sorted() {
      try Task.checkCancellation()
      offsets[reference] = Int64(output.count)
      output.appendASCII("\(reference.objectNumber) \(reference.generationNumber) obj\n")
      guard let body = objects[reference] else { throw PDFIncrementalUpdateError.validationFailed }
      switch body {
      case .value(let value):
        output.append(try serializer.serialize(value))
      case .stream(var dictionary, let bytes):
        guard bytes.count <= limits.maximumAppearanceStreamBytes else {
          throw PDFIncrementalUpdateError.limitExceeded
        }
        dictionary["Length"] = .integer(bytes.count)
        output.append(try serializer.serialize(.dictionary(dictionary)))
        output.appendASCII("\nstream\n")
        output.append(bytes)
        output.appendASCII("\nendstream")
      }
      output.appendASCII("\nendobj\n")
      try checkOutput(output, appendedStart: appendedStart)
    }

    let size = max(
      Int(revision.trailer.pdfInteger(named: "Size") ?? 0),
      (objects.keys.map(\.objectNumber).max() ?? 0) + 1
    )
    let identifier = identifiers(output)
    let representation: PDFCrossReferenceRepresentation
    let startCrossReferenceOffset: Int64
    switch revision.representation {
    case .classic, .hybrid:
      representation = .classic
      startCrossReferenceOffset = Int64(output.count)
      try appendClassicCrossReference(
        offsets: offsets,
        size: size,
        identifiers: identifier,
        to: &output
      )
    case .stream:
      representation = .stream
      let xrefNumber = size
      let xrefReference = PDFObjectReference(uncheckedObjectNumber: xrefNumber, generationNumber: 0)
      startCrossReferenceOffset = Int64(output.count)
      try appendCrossReferenceStream(
        offsets: offsets,
        reference: xrefReference,
        size: xrefNumber + 1,
        identifiers: identifier,
        to: &output
      )
    }
    try checkOutput(output, appendedStart: appendedStart)
    return EncodedRevision(
      data: output,
      appendedByteCount: output.count - original.count,
      startCrossReferenceOffset: startCrossReferenceOffset,
      representation: representation
    )
  }

  private var writerLimits: PDFWritingLimits {
    PDFWritingLimits(
      maximumObjectCount: limits.maximumAppendedObjects,
      maximumObjectNesting: 256,
      maximumStreamBytes: limits.maximumAppearanceStreamBytes,
      maximumOutputBytes: Int(min(Int64(Int.max), limits.maximumStagedDocumentBytes)),
      maximumTemporaryBytes: limits.maximumValidationScratchBytes
    )
  }

  private func validateLimits() throws {
    guard limits.maximumFieldUpdates > 0,
      limits.maximumAppendedObjects > 0,
      limits.maximumAppearanceStreamBytes >= 0,
      limits.maximumAppendedBytes > 0,
      limits.maximumStagedDocumentBytes > 0,
      limits.maximumValidationScratchBytes >= 0,
      objects.count <= limits.maximumAppendedObjects,
      Int64(original.count) <= limits.maximumStagedDocumentBytes
    else { throw PDFIncrementalUpdateError.limitExceeded }
  }

  private func checkOutput(_ output: Data, appendedStart: Int) throws {
    guard output.count - appendedStart <= limits.maximumAppendedBytes,
      Int64(output.count) <= limits.maximumStagedDocumentBytes
    else { throw PDFIncrementalUpdateError.limitExceeded }
  }

  private func identifiers(_ prefix: Data) -> [PDFString] {
    let permanent = revision.fileIdentifier?.first?.bytes ?? PDFCrypto.sha256(original).prefix(16)
    var changingInput = Data(permanent)
    changingInput.append(prefix.suffix(from: original.count))
    let changing = PDFCrypto.sha256(changingInput).prefix(16)
    return [
      PDFString(bytes: Data(permanent), representation: .hexadecimal),
      PDFString(bytes: Data(changing), representation: .hexadecimal),
    ]
  }

  private func trailer(size: Int, identifiers: [PDFString]) -> [PDFName: PDFObject] {
    var trailer: [PDFName: PDFObject] = [
      "Size": .integer(size),
      "Root": .reference(revision.root),
      "Prev": .integer(Int(revision.startCrossReferenceOffset)),
      "ID": .array(identifiers.map(PDFObject.string)),
    ]
    if let info = revision.info { trailer["Info"] = .reference(info) }
    if let encryption = revision.encryptionObject { trailer["Encrypt"] = encryption }
    return trailer
  }

  private func appendClassicCrossReference(
    offsets: [PDFObjectReference: Int64],
    size: Int,
    identifiers: [PDFString],
    to output: inout Data
  ) throws {
    let start = output.count
    output.appendASCII("xref\n")
    let entries = [(0, Int64(0), 65_535, false)] + offsets.keys.sorted().map { reference in
      (reference.objectNumber, offsets[reference] ?? 0, reference.generationNumber, true)
    }
    for group in contiguousGroups(entries) {
      output.appendASCII("\(group[0].0) \(group.count)\n")
      for entry in group {
        guard entry.1 <= 9_999_999_999 else { throw PDFIncrementalUpdateError.limitExceeded }
        output.appendASCII(String(format: "%010lld %05d %@ \n", entry.1, entry.2, entry.3 ? "n" : "f"))
      }
    }
    output.appendASCII("trailer\n")
    output.append(try PDFObjectSerializer(limits: writerLimits).serialize(
      .dictionary(trailer(size: size, identifiers: identifiers))
    ))
    output.appendASCII("\nstartxref\n\(start)\n%%EOF\n")
  }

  private func appendCrossReferenceStream(
    offsets: [PDFObjectReference: Int64],
    reference: PDFObjectReference,
    size: Int,
    identifiers: [PDFString],
    to output: inout Data
  ) throws {
    var allOffsets = offsets
    allOffsets[reference] = Int64(output.count)
    let numbers = [0] + allOffsets.keys.map(\.objectNumber).sorted()
    let groups = contiguousNumberGroups(numbers)
    var bytes = Data()
    for number in numbers {
      if number == 0 {
        bytes.append(0)
        appendBigEndian(0, width: 8, to: &bytes)
        appendBigEndian(65_535, width: 2, to: &bytes)
      } else {
        guard let item = allOffsets.first(where: { $0.key.objectNumber == number }) else {
          throw PDFIncrementalUpdateError.validationFailed
        }
        bytes.append(1)
        appendBigEndian(UInt64(item.value), width: 8, to: &bytes)
        appendBigEndian(UInt64(item.key.generationNumber), width: 2, to: &bytes)
      }
    }
    var dictionary = trailer(size: size, identifiers: identifiers)
    dictionary["Type"] = .name("XRef")
    dictionary["W"] = .array([.integer(1), .integer(8), .integer(2)])
    dictionary["Index"] = .array(groups.flatMap { [.integer($0.lowerBound), .integer($0.count)] })
    dictionary["Length"] = .integer(bytes.count)
    output.appendASCII("\(reference.objectNumber) 0 obj\n")
    output.append(try PDFObjectSerializer(limits: writerLimits).serialize(.dictionary(dictionary)))
    output.appendASCII("\nstream\n")
    output.append(bytes)
    output.appendASCII("\nendstream\nendobj\nstartxref\n\(allOffsets[reference] ?? 0)\n%%EOF\n")
  }

  private func contiguousGroups(
    _ entries: [(Int, Int64, Int, Bool)]
  ) -> [[(Int, Int64, Int, Bool)]] {
    var groups = [[(Int, Int64, Int, Bool)]]()
    for entry in entries {
      if groups.last?.last.map({ $0.0 + 1 == entry.0 }) == true {
        groups[groups.count - 1].append(entry)
      } else {
        groups.append([entry])
      }
    }
    return groups
  }

  private func contiguousNumberGroups(_ numbers: [Int]) -> [Range<Int>] {
    var groups = [Range<Int>]()
    for number in numbers {
      if let last = groups.last, last.upperBound == number {
        groups[groups.count - 1] = last.lowerBound..<(number + 1)
      } else {
        groups.append(number..<(number + 1))
      }
    }
    return groups
  }

  private func appendBigEndian(_ value: UInt64, width: Int, to data: inout Data) {
    for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
      data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
  }
}
