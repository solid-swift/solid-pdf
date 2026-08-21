import Foundation
import SolidIO

/// A uniquely owned deterministic PDF document writer.
public struct PDFDocumentWriter<Sink: PDFOutputSink>: ~Copyable {
  private struct Entry {
    var body: Data?
    var references = Set<PDFObjectReference>()
  }

  private let options: PDFWritingOptions
  private var sink: Sink.Session?
  private var entries = [Entry(body: nil)]
  private var temporaryBytes = 0
  private var finished = false

  /// Creates a writer and its isolated output session.
  public init(sink: Sink, options: PDFWritingOptions = .init()) throws {
    self.options = options
    self.sink = nil
    guard (-1...9).contains(options.compressionLevel),
      options.limits.maximumObjectCount > 0,
      options.limits.maximumObjectNesting > 0,
      options.limits.maximumStreamBytes >= 0,
      options.limits.maximumOutputBytes > 0,
      options.limits.maximumTemporaryBytes >= 0
    else { throw PDFError.invalidObject }
    self.sink = try sink.makeSession()
  }

  deinit {
    if !finished { sink?.abort() }
  }

  /// Reserves an indirect reference that may be used before its object is defined.
  public mutating func reserveObject() throws -> PDFObjectReference {
    try requireOpen()
    guard entries.count <= options.limits.maximumObjectCount else {
      throw PDFError.limitExceeded
    }
    entries.append(Entry(body: nil))
    return PDFObjectReference(objectNumber: entries.count - 1)
  }

  /// Defines a reserved indirect object.
  public mutating func write(_ object: PDFObject, to reference: PDFObjectReference) throws {
    try requireOpen()
    guard entries.indices.contains(reference.objectNumber),
      reference.objectNumber != 0,
      entries[reference.objectNumber].body == nil
    else { throw PDFError.invalidReference }
    let serializer = PDFObjectSerializer(limits: options.limits)
    let body = try serializer.serialize(object)
    let references = try serializer.references(in: object)
    try reserveTemporary(body.count)
    entries[reference.objectNumber] = Entry(body: body, references: references)
  }

  /// Defines a reserved stream object from bounded input chunks.
  public mutating func writeStream<Chunks: Sequence>(
    dictionary: [PDFName: PDFObject] = [:],
    chunks: Chunks,
    compressed: Bool = true,
    to reference: PDFObjectReference
  ) throws where Chunks.Element == Data {
    try requireOpen()
    guard entries.indices.contains(reference.objectNumber),
      reference.objectNumber != 0,
      entries[reference.objectNumber].body == nil
    else { throw PDFError.invalidReference }

    let lengthReference = try reserveObject()
    var streamData = Data()
    var inputCount = 0
    let compressor: ZlibStreamEncoder? = try compressed
      ? ZlibStreamEncoder(compressionLevel: options.compressionLevel)
      : nil
    do {
      for chunk in chunks {
        inputCount = try Self.checkedSum(inputCount, chunk.count)
        guard inputCount <= options.limits.maximumStreamBytes else { throw PDFError.limitExceeded }
        if let compressor {
          streamData.append(try compressor.process(chunk))
        } else {
          streamData.append(chunk)
        }
        guard streamData.count <= options.limits.maximumTemporaryBytes else {
          throw PDFError.limitExceeded
        }
      }
      if let compressor { streamData.append(try compressor.finish() ?? Data()) }
    } catch let error as PDFError {
      throw error
    } catch {
      throw PDFError.compressionFailure
    }

    var values = dictionary
    values["Length"] = .reference(lengthReference)
    if compressed { values["Filter"] = .name("FlateDecode") }
    let serializer = PDFObjectSerializer(limits: options.limits)
    var body = try serializer.serialize(.dictionary(values))
    body.appendASCII("\nstream\n")
    body.append(streamData)
    body.appendASCII("\nendstream")
    try reserveTemporary(body.count)
    entries[reference.objectNumber] = Entry(
      body: body,
      references: try serializer.references(in: .dictionary(values))
    )
    try write(.integer(streamData.count), to: lengthReference)
  }

  /// Abandons construction and deletes any staged output.
  public consuming func abort() {
    guard !finished else { return }
    finished = true
    sink?.abort()
  }

  /// Finalizes and publishes the document.
  public consuming func finish(
    root: PDFObjectReference,
    info: PDFObjectReference? = nil,
    pageCount: Int,
    diagnostics: [PDFDiagnostic] = []
  ) throws -> sending Sink.Session.Output {
    try requireOpen()
    do {
      guard pageCount >= 0 else { throw PDFError.invalidObject }
      try validate(root: root, info: info)
      let bytes = try encode(root: root, info: info)
      guard bytes.count <= options.limits.maximumOutputBytes else { throw PDFError.limitExceeded }
      guard let sink else { throw PDFError.outputFailure }
      try sink.write(bytes)
      finished = true
      return try sink.finish(
        version: options.version,
        pageCount: pageCount,
        diagnostics: diagnostics
      )
    } catch {
      finished = true
      sink?.abort()
      throw error
    }
  }

  private mutating func reserveTemporary(_ count: Int) throws {
    temporaryBytes = try Self.checkedSum(temporaryBytes, count)
    guard temporaryBytes <= options.limits.maximumTemporaryBytes else {
      throw PDFError.limitExceeded
    }
  }

  private func requireOpen() throws {
    guard !finished else { throw PDFError.writerFinished }
  }

  private func validate(root: PDFObjectReference, info: PDFObjectReference?) throws {
    guard entries.indices.contains(root.objectNumber), root.objectNumber != 0 else {
      throw PDFError.invalidReference
    }
    if let info {
      guard entries.indices.contains(info.objectNumber), info.objectNumber != 0 else {
        throw PDFError.invalidReference
      }
    }
    for (index, entry) in entries.enumerated() where index != 0 {
      guard entry.body != nil else {
        throw PDFError.unresolvedReference(PDFObjectReference(objectNumber: index))
      }
      for reference in entry.references {
        guard entries.indices.contains(reference.objectNumber),
          entries[reference.objectNumber].body != nil
        else { throw PDFError.unresolvedReference(reference) }
      }
    }
  }

  private func encode(root: PDFObjectReference, info: PDFObjectReference?) throws -> Data {
    var output = Data()
    output.appendASCII("%PDF-\(options.version.rawValue)\n")
    output.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
    var offsets = [Int64](repeating: 0, count: entries.count)
    for number in 1..<entries.count {
      offsets[number] = Int64(output.count)
      output.appendASCII("\(number) 0 obj\n")
      guard let body = entries[number].body else { throw PDFError.invalidReference }
      output.append(body)
      output.appendASCII("\nendobj\n")
      guard output.count <= options.limits.maximumOutputBytes else { throw PDFError.limitExceeded }
    }
    let identifier = Self.identifier(for: output)
    switch options.version {
    case .v1_7:
      try appendCrossReferenceTable(
        offsets: offsets,
        root: root,
        info: info,
        identifier: identifier,
        to: &output
      )
    case .v2_0:
      try appendCrossReferenceStream(
        offsets: offsets,
        root: root,
        info: info,
        identifier: identifier,
        to: &output
      )
    }
    return output
  }

  private func appendCrossReferenceTable(
    offsets: [Int64],
    root: PDFObjectReference,
    info: PDFObjectReference?,
    identifier: Data,
    to output: inout Data
  ) throws {
    let start = output.count
    output.appendASCII("xref\n0 \(offsets.count)\n")
    output.appendASCII("0000000000 65535 f \n")
    for offset in offsets.dropFirst() {
      guard offset <= 9_999_999_999 else { throw PDFError.limitExceeded }
      output.appendASCII(String(format: "%010lld 00000 n \n", offset))
    }
    var trailer: [PDFName: PDFObject] = [
      "Size": .integer(offsets.count),
      "Root": .reference(root),
      "ID": .array([
        .string(PDFString(bytes: identifier, representation: .hexadecimal)),
        .string(PDFString(bytes: identifier, representation: .hexadecimal)),
      ]),
    ]
    if let info { trailer["Info"] = .reference(info) }
    output.appendASCII("trailer\n")
    output.append(try PDFObjectSerializer(limits: options.limits).serialize(.dictionary(trailer)))
    output.appendASCII("\nstartxref\n\(start)\n%%EOF\n")
  }

  private func appendCrossReferenceStream(
    offsets: [Int64],
    root: PDFObjectReference,
    info: PDFObjectReference?,
    identifier: Data,
    to output: inout Data
  ) throws {
    let objectNumber = offsets.count
    let start = output.count
    var crossReference = Data()
    crossReference.append(0)
    crossReference.appendBigEndian(UInt64(0))
    crossReference.appendBigEndian(UInt16.max)
    for offset in offsets.dropFirst() {
      crossReference.append(1)
      crossReference.appendBigEndian(UInt64(offset))
      crossReference.appendBigEndian(UInt16(0))
    }
    crossReference.append(1)
    crossReference.appendBigEndian(UInt64(start))
    crossReference.appendBigEndian(UInt16(0))
    var dictionary: [PDFName: PDFObject] = [
      "Type": .name("XRef"),
      "Size": .integer(objectNumber + 1),
      "Root": .reference(root),
      "W": .array([.integer(1), .integer(8), .integer(2)]),
      "Length": .integer(crossReference.count),
      "ID": .array([
        .string(PDFString(bytes: identifier, representation: .hexadecimal)),
        .string(PDFString(bytes: identifier, representation: .hexadecimal)),
      ]),
    ]
    if let info { dictionary["Info"] = .reference(info) }
    output.appendASCII("\(objectNumber) 0 obj\n")
    output.append(try PDFObjectSerializer(limits: options.limits).serialize(.dictionary(dictionary)))
    output.appendASCII("\nstream\n")
    output.append(crossReference)
    output.appendASCII("\nendstream\nendobj\nstartxref\n\(start)\n%%EOF\n")
  }

  private static func checkedSum(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw PDFError.limitExceeded }
    return result
  }

  private static func identifier(for data: Data) -> Data {
    var first: UInt64 = 0xCBF2_9CE4_8422_2325
    var second: UInt64 = 0x8422_2325_CBF2_9CE4
    for byte in data {
      first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
      second = (second ^ UInt64(byte &+ 0x9D)) &* 0x0000_0100_0000_01B3
    }
    var output = Data()
    output.appendBigEndian(first)
    output.appendBigEndian(second)
    return output
  }
}

private extension Data {
  mutating func appendBigEndian(_ value: UInt16) {
    append(contentsOf: [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
  }

  mutating func appendBigEndian(_ value: UInt64) {
    for shift in stride(from: 56, through: 0, by: -8) {
      append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
  }
}
